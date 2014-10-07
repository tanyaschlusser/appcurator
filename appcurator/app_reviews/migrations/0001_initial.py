# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.db import models, migrations


class Migration(migrations.Migration):

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='AppDescription',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('description', models.CharField(max_length=512)),
                ('icon_uri', models.CharField(max_length=512)),
                ('pub_date', models.DateTimeField(verbose_name=b'date of review')),
            ],
            options={
            },
            bases=(models.Model,),
        ),
        migrations.CreateModel(
            name='Rating',
            fields=[
                ('id', models.AutoField(verbose_name='ID', serialize=False, auto_created=True, primary_key=True)),
                ('rating', models.CharField(max_length=8)),
                ('votes', models.IntegerField(default=0)),
                ('description', models.ForeignKey(to='app_reviews.AppDescription')),
            ],
            options={
            },
            bases=(models.Model,),
        ),
    ]
