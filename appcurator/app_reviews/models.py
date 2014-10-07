from django.db import models

# Create your models here.
class AppDescription(models.Model):
    description = models.CharField(max_length=512)
    icon_uri = models.CharField(max_length=512)
    pub_date = models.DateTimeField('date of review')

class Rating(models.Model):
    description = models.ForeignKey(AppDescription)
    rating = models.CharField(max_length=8)
    votes = models.IntegerField(default=0)
