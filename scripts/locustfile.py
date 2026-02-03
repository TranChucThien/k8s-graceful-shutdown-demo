from locust import HttpUser, task, between, events
import json
import os

# Configuration from environment variables
ACCOUNT = os.getenv('ACCOUNT', 'ACC001')
AMOUNT = int(os.getenv('AMOUNT', '10000'))

# Global counters
successful_deposits = 0
failed_deposits = 0
completed_transactions = 0
failed_transactions = 0


class BankingUser(HttpUser):
    wait_time = between(1, 2)
    
    @task
    def deposit(self):
        global successful_deposits, failed_deposits
        
        payload = {
            "accountNumber": ACCOUNT,
            "amount": AMOUNT
        }
        
        with self.client.post(
            "/api/deposit",
            json=payload,
            catch_response=True
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    if data.get('status') == 'COMPLETED':
                        successful_deposits += 1
                        response.success()
                    else:
                        failed_deposits += 1
                        response.failure(f"Transaction not completed: {data.get('status')}")
                except json.JSONDecodeError:
                    failed_deposits += 1
                    response.failure("Invalid JSON response")
            else:
                failed_deposits += 1
                response.failure(f"HTTP {response.status_code}")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Print summary when test stops"""
    print("\n" + "="*60)
    print("📊 Locust Test Summary")
    print("="*60)
    print(f"✅ Successful Deposits: {successful_deposits}")
    print(f"❌ Failed Deposits: {failed_deposits}")
    
    total = successful_deposits + failed_deposits
    if total > 0:
        success_rate = (successful_deposits / total) * 100
        print(f"📈 Success Rate: {success_rate:.2f}%")
    
    print("="*60)
