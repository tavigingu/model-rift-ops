#!/usr/bin/env python3
"""
Test script for KServe fraud detection model endpoint.
Sends sample prediction requests to the deployed InferenceService.
"""

import requests
import numpy as np
import json
import sys
import argparse

def generate_sample_transaction(fraud=False):
    """Generate a sample transaction with 29 features (V1-V28 + Amount)."""
    np.random.seed(None)  # Random seed for variety
    
    if fraud:
        # Fraud transactions: higher values, different distribution
        features = np.random.randn(28) + 2  # V1-V28
        amount = np.random.gamma(3, 100)     # Higher amounts
    else:
        # Normal transactions
        features = np.random.randn(28)       # V1-V28
        amount = np.random.gamma(2, 50)      # Normal amounts
    
    # Combine features and amount
    transaction = np.append(features, amount).tolist()
    return transaction

def test_inference(endpoint_url, num_samples=5):
    """
    Test the KServe inference endpoint with sample transactions.
    
    Args:
        endpoint_url: Full URL to the prediction endpoint
        num_samples: Number of test samples to send
    """
    print(f"🧪 Testing KServe Inference Endpoint")
    print(f"=" * 60)
    print(f"Endpoint: {endpoint_url}")
    print(f"Samples: {num_samples}")
    print(f"=" * 60)
    print()
    
    # Generate test samples (mix of fraud and normal)
    samples = []
    labels = []
    for i in range(num_samples):
        is_fraud = i % 3 == 0  # Every 3rd sample is "fraud-like"
        samples.append(generate_sample_transaction(fraud=is_fraud))
        labels.append("Fraud-like" if is_fraud else "Normal-like")
    
    # Prepare request payload
    payload = {
        "instances": samples
    }
    
    print(f"📤 Sending {num_samples} transactions for prediction...")
    print()
    
    try:
        # Send POST request
        response = requests.post(
            endpoint_url,
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=30
        )
        
        # Check response status
        if response.status_code == 200:
            print("✅ Request successful!")
            print()
            
            # Parse predictions
            result = response.json()
            predictions = result.get("predictions", [])
            
            # Display results
            print(f"📊 Prediction Results:")
            print(f"-" * 60)
            for i, (pred, label) in enumerate(zip(predictions, labels)):
                fraud_prob = pred if isinstance(pred, (int, float)) else pred[1] if isinstance(pred, list) else pred
                print(f"Transaction {i+1} ({label:12s}): Fraud Probability = {fraud_prob:.4f}")
            
            print(f"-" * 60)
            print()
            print(f"✅ All predictions completed successfully!")
            
        else:
            print(f"❌ Request failed with status code: {response.status_code}")
            print(f"Response: {response.text}")
            sys.exit(1)
            
    except requests.exceptions.ConnectionError:
        print(f"❌ Connection Error: Could not connect to {endpoint_url}")
        print()
        print("Make sure you have port-forwarding enabled:")
        print("  kubectl port-forward -n kubeflow-user-example-com svc/fraud-detection-predictor-default 8080:80")
        sys.exit(1)
        
    except requests.exceptions.Timeout:
        print(f"❌ Timeout: Request took too long")
        sys.exit(1)
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Test KServe fraud detection endpoint")
    parser.add_argument(
        "--endpoint",
        default="http://localhost:8080/v1/models/fraud-detection:predict",
        help="Prediction endpoint URL (default: localhost:8080)"
    )
    parser.add_argument(
        "--samples",
        type=int,
        default=5,
        help="Number of test samples (default: 5)"
    )
    
    args = parser.parse_args()
    
    test_inference(args.endpoint, args.samples)

if __name__ == "__main__":
    main()
