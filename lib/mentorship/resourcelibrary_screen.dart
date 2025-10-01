import 'package:flutter/material.dart';

class ResourceLibraryScreen extends StatelessWidget {
  final List<Map<String, String>> resources = [
    {
      'title': "Python Best Practices",
      'category': "Programming Language",
      'description': "Improve your Python coding skills with efficient techniques and design patterns.",
      'link': "https://realpython.com"
    },
    {
      'title': "Advanced Java Programming",
      'category': "Software Development",
      'description': "Master Java concepts, from concurrency to design patterns and optimizations.",
      'link': "https://docs.oracle.com/javase/tutorial/"
    },
    {
      'title': "C# for Modern Applications",
      'category': "Application Development",
      'description': "Learn C# for building desktop, web, and mobile applications using .NET.",
      'link': "https://learn.microsoft.com/en-us/dotnet/csharp/"
    },
    {
      'title': "VB.NET Essentials",
      'category': "Windows Development",
      'description': "Explore VB.NET’s capabilities for rapid application development in the .NET ecosystem.",
      'link': "https://learn.microsoft.com/en-us/dotnet/visual-basic/"
    },
  ];

  ResourceLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Resource Library'), backgroundColor: Colors.indigo),
      body: ListView.builder(
        itemCount: resources.length,
        itemBuilder: (context, index) {
          return Card(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            elevation: 5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text(resources[index]['title']!, style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Category: ${resources[index]['category']}"),
                  Text("Description: ${resources[index]['description']}"),
                ],
              ),
              leading: Icon(Icons.book, size: 40, color: Colors.indigo),
              trailing: IconButton(
                icon: Icon(Icons.download_rounded, color: Colors.green),
                onPressed: () {
                  // Placeholder action for opening the resource link
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Opening ${resources[index]['title']} resource...")),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}