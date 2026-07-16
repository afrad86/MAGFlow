CSS = """
body {
    font-family: Arial, Helvetica, sans-serif;
    margin: 40px;
    background: #f5f5f5;
    color: #222;
}

h1 {
    color: #0b5394;
    margin-bottom: 5px;
}

h2 {
    color: #444;
    margin-top: 35px;
}

table {
    border-collapse: collapse;
    width: 700px;
    background: white;
    margin-bottom: 30px;
}

th {
    background: #0b5394;
    color: white;
    text-align: left;
}

th,
td {
    border: 1px solid #dddddd;
    padding: 8px 12px;
}

tr:nth-child(even) {
    background: #f8f8f8;
}

.footer {
    margin-top: 40px;
    color: gray;
    font-size: 12px;
}

.cards {
    display: flex;
    flex-wrap: wrap;
    gap: 20px;
    margin-bottom: 35px;
}

.card {
    background: white;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.12);
    padding: 20px;
    width: 150px;
    text-align: center;
}

.card-title {
    font-size: 14px;
    color: #666;
}

.card-value {
    font-size: 34px;
    font-weight: bold;
    color: #0b5394;
    margin-top: 10px;
}

.bar-table {
    width: 700px;
    border-collapse: collapse;
    margin-bottom: 35px;
}

.bar-table td {
    border: none;
    padding: 8px;
}

.bar-bg {
    width: 400px;
    height: 22px;
    background: #eeeeee;
    border-radius: 5px;
}

.bar-fill {
    height: 22px;
    border-radius: 5px;
}

.high {
    background: #4CAF50;
}

.medium {
    background: #FFC107;
}

.low {
    background: #E53935;
}

.badge {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 14px;
    color: white;
    font-weight: bold;
    font-size: 12px;
}

.badge-high {
    background: #4CAF50;
}

.badge-medium {
    background: #FFC107;
    color: black;
}

.badge-low {
    background: #E53935;
}

.badge-pass {
    background: #4CAF50;
}

.badge-fail {
    background: #E53935;
}
"""