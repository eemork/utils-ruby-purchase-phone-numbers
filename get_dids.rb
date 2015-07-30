# Phone Number Provisioning Script
# Script name: get_dids

# Author: Andy Jiang, @andyjiang, andy@twilio.com
# Date: 12/24/2013
# Description:
#   Some enterprise customers need to quickly provision many phone numbers (in the thousands).
# Currently, the only way to do this is for the customer to write scripts using Twilio's REST API or
# have Twilio's Phone Number team provision them manually. It is both a time consuming and laborious
# process. This script can be a tool that is self-service to be used internally and externally.
#   This script can be easily run from the command line by customers, Twilio Ops team, or Sales
# engineers.

# Include the following libraries.
require 'csv'

# Import modified Twilio-Ruby wrapper library locally.
require 'twilio-ruby'

# Parameters:
# - TWILIO_ACCOUNT_SID
# - TWILIO_ACCOUNT_TOKEN
# - CUSTOMER_ACCOUNT_SID
# - INPUT_FILE_NAME (a csv file: areacode/zip code, requested quantity)
TWILIO_ACCOUNT_SID, TWILIO_ACCOUNT_TOKEN, INPUT_FILE_NAME = ARGV

# Action:
# Script will search for available phone numbers either for that area code or zip code.

# Output:
# Another CSV file will be generated: areacode/zipcode, requested quantity, provisioned quantity
# output.csv

# Initialize variables.
@client = Twilio::REST::Client.new TWILIO_ACCOUNT_SID, TWILIO_ACCOUNT_TOKEN
csv_input = File.open(INPUT_FILE_NAME)


# Parse the csv file and turn it into an array of hashes: 'location', 'quantity_requested'
puts " ..Reading and parsing #{INPUT_FILE_NAME}."
did_request = Array.new								# This variable is an array for the CSV file.
CSV.parse(csv_input) do |row|
	obj = Hash.new
	obj['location'] = row[0] 						# Note, this can be zip code or area code.
	obj['quantity_requested'] = row[1]
	did_request.push(obj)
end

# First need to get available phone numbers.
# Remove CSV header row from array
did_request.shift(1)
did_request.each { |i|
	# @available_numbers is an array will store max of 30 available phone numbers from Twilio number search API.
	@available_numbers = Array.new
	# @provisioned_phone_numbers is the array of actually provisioned phone numbers.
	@provisioned_phone_numbers = Array.new
	quantity_requested = i['quantity_requested'].to_i

	puts " ..Searching for #{quantity_requested} phone numbers in #{i['location']}."

	# Begin a do..while loop to continue to add numbers should the quantity requested exceeds 30.
	begin
		# You can only get 30 phone numbers at a time.
		# Get 30 or quantity_requested number of available phone numbers.
		# Put that into @available_numbers
		# if quantity_requested > 30, then get 30

		puts " ..Getting available phone numbers from Twilio in #{i['location']}."
		# Check if the location is zip code or area code.
		if i['location'].length == 3
			@available_numbers = @client.account.available_phone_numbers.get('US').local.list(:area_code => i['location'])
		elsif i['location'].length == 5
			@available_numbers = @client.account.available_phone_numbers.get('US').local.list(:postal_code => i['location'])
		end

		if @available_numbers.length == 0
			# If there are no more available phone numbers.
			puts "No more available phone numbers in #{i['location']}."
			break
		end

		# If number search API returns fewer than quantity requested, then remove the difference.
		if (@available_numbers.length - quantity_requested) > 0
			@available_numbers.shift(@available_numbers.length - quantity_requested)
		end

		puts " ..Found #{@available_numbers.length} available phone numbers in #{i['location']}."

		# Purchase the numbers in @available_numbers.
		puts " ..Purchasing #{@available_numbers.length} phone numbers in #{i['location']}."

		# Provision each of them. Add provisioned phone number to @provisioned_phone_numbers
		provisioned = 0
		@available_numbers.each { |number|
			# puts number.phone_number

			# Twilio's API will return an error if you try to buy a number that is not available.
			begin
				# Get the phone number.
				@client.account.incoming_phone_numbers.create(:phone_number => number.phone_number)

				# Add provisioned number to array.
				@provisioned_phone_numbers.push(number.phone_number)

				# Increment provisioned.
				provisioned += 1
		  rescue
		  	# Error.
		  	puts " ..There is an error; #{number.phone_number} is either invalid or unavailable."
		  end
		}

		quantity_requested = quantity_requested - provisioned

		@available_numbers.clear
		# end when quantity_requested = provisioned_phone_numbers.length OR no more available phone numbers in that area.
	end while quantity_requested > 0

	puts "Completed provisioning #{@provisioned_phone_numbers.length} phone numbers in #{i['location']}."

	# Initialize quantity provisioned for this location.
	i['quantity_provisioned'] = @provisioned_phone_numbers.length

	# Assign array of provisioned phone numbers to i['provisioned_phone_numbers']
	i['provisioned_phone_numbers'] = @provisioned_phone_numbers.join(" ")

	# DEBUGGING.
	uniques = @provisioned_phone_numbers.uniq
	if uniques.length == @provisioned_phone_numbers.length
		puts "****** SUCCESS: ALL UNIQUE PHONE NUMBERS ******"
		puts "There are actually #{uniques.length} unique phone numbers."
	else
		puts "****** FAILURE: THERE ARE DUPLICATES *******"
		puts "There are actually #{uniques.length} unique phone numbers."
	end

	# Reinitialize the numbers array.
	@provisioned_phone_numbers.clear
}

# Return a CSV file.
puts " ..Writing results to output.csv file."
# area code/zip code, quantity requested, quantity provisioned
CSV.open('output.csv', 'w') do |csv|
	csv << ['Location','Quantity Requested', 'Quantity Provisioned', 'Provisioned Phone Numbers']
	did_request.each { |i|
		csv << [i['location'], i['quantity_requested'], i['quantity_provisioned'], i['provisioned_phone_numbers']]
	}
end