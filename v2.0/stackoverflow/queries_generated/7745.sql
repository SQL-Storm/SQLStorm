-- {"query": "7745.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 6853} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScorePosts,
    COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) as NegativeScorePosts,
    AVG(CAST(p.Score AS FLOAT)) as AvgScore,
    MAX(p.CreationDate) as LatestActivity,
    DATEDIFF(day, u.CreationDate, u.LastAccessDate) as DaysSinceRegistration,
    CASE 
        WHEN u.Reputation >= 10000 THEN 'Elite'
        WHEN u.Reputation >= 1000 THEN 'Veteran'
        WHEN u.Reputation >= 100 THEN 'Member'
        ELSE 'Newbie'
    END as ReputationTier,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 2 
        AND p3.Score > 0
    ) as UpvotedAnswers,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId = 2
    ) as UpvotesGiven,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId = 3
    ) as DownvotesGiven,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId = 5
    ) as Favorites,
    (
        SELECT STRING_AGG(DISTINCT t.TagName, ', ')
        FROM Posts p4
        INNER JOIN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
        ) pq ON p4.ParentId = pq.Id
        LEFT JOIN (
            SELECT Id, TagName FROM Tags
        ) t ON p4.Tags LIKE '%' + t.TagName + '%'
        WHERE p4.PostTypeId = 4
    ) as TagBasedBadges,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    ) as EditHistoryCount,
    (
        SELECT COUNT(*) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.ViewCount > 1000
    ) as HighViewPosts,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
    DENSE_RANK() OVER (ORDER BY AVG(CAST(p.Score AS FLOAT)) DESC) as AvgScoreRank,
    NTILE(10) OVER (ORDER BY u.Reputation) as ReputationDecile,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) THEN 'GoldBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) THEN 'SilverBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) THEN 'BronzeBadgeHolder'
        ELSE 'NoBadge'
    END as BadgeStatus,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) as NextReputation,
    CASE 
        WHEN u.Reputation > (
            SELECT AVG(Reputation) FROM Users
        ) * 1.5 THEN 'AboveAverage'
        WHEN u.Reputation > (
            SELECT AVG(Reputation) FROM Users
        ) THEN 'Average'
        ELSE 'BelowAverage'
    END as RepComparison,
    COALESCE(u.WebsiteUrl, 'No Website') as Website,
    COALESCE(u.Location, 'Unknown Location') as Location,
    (
        SELECT TOP 1 Text 
        FROM Comments c2 
        WHERE c2.UserId = u.Id 
        ORDER BY c2.CreationDate DESC
    ) as RecentComment,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.PostTypeId = 1 
        AND p6.AnswerCount > 10
    ) as QuestionWithManyAnswers,
    ABS(
        (
            SELECT AVG(p7.Score) 
            FROM Posts p7 
            WHERE p7.OwnerUserId = u.Id 
            AND p7.PostTypeId = 1
        ) - 
        (
            SELECT AVG(Reputation) 
            FROM Users
        )
    ) as ReputationDeviation,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id))
        ELSE 0 
    END as QuestionPercentage,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        INNER JOIN Posts p8 ON pl.PostId = p8.Id 
        WHERE p8.OwnerUserId = u.Id 
        AND pl.LinkTypeId = 1
    ) as LinkedPosts,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.PostHistoryTypeId = 10
    ) as CloseVotes,
    (
        SELECT 
            STRING_AGG(
                CASE 
                    WHEN ph3.PostHistoryTypeId = 10 THEN 'Closed'
                    WHEN ph3.PostHistoryTypeId = 11 THEN 'Reopened'
                    WHEN ph3.PostHistoryTypeId = 12 THEN 'Deleted'
                    WHEN ph3.PostHistoryTypeId = 13 THEN 'Undeleted'
                    ELSE 'Other'
                END, 
                ', '
            )
        FROM PostHistory ph3 
        WHERE ph3.UserId = u.Id
    ) as ActivityTypes,
    (
        SELECT TOP 1 Title 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 1
        ORDER BY p9.CreationDate DESC
    ) as LatestQuestionTitle,
    (
        SELECT COUNT(*) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 1 
        AND p10.Score > 10
    ) as HighScoreQuestions,
    (
        SELECT AVG(VotesGiven) 
        FROM (
            SELECT COUNT(*) as VotesGiven
            FROM Votes v2 
            WHERE v2.UserId = u.Id
            GROUP BY DATEADD(day, 0, v2.CreationDate)
        ) VoteCounts
    ) as AvgDailyVotes,
    (
        SELECT COUNT(*) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id 
        AND p11.LastEditDate > p11.CreationDate
    ) as EditedPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p12 
        WHERE p12.OwnerUserId = u.Id 
        AND p12.PostTypeId = 1 
        AND p12.Tags IS NOT NULL
    ) as TaggedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p13 
        WHERE p13.OwnerUserId = u.Id 
        AND p13.PostTypeId = 2 
        AND p13.AcceptedAnswerId IS NOT NULL
    ) as AcceptedAnswers,
    (
        SELECT COUNT(*) 
        FROM Votes v3 
        WHERE v3.UserId = u.Id 
        AND v3.VoteTypeId = 1
    ) as Acceptances,
    (
        SELECT AVG(CAST(p14.Score AS FLOAT))
        FROM Posts p14 
        WHERE p14.OwnerUserId = u.Id 
        AND p14.PostTypeId = 2
    ) as AvgAnswerScore,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN u2.Reputation > u.Reputation THEN 'Higher'
                WHEN u2.Reputation < u.Reputation THEN 'Lower'
                ELSE 'Equal'
            END, 
            ', '
        )
        FROM Users u2
        WHERE u2.Reputation BETWEEN u.Reputation - 1000 AND u.Reputation + 1000
        AND u2.Id <> u.Id
        AND u2.Reputation IS NOT NULL
        ORDER BY u2.Reputation
        OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
    ) as ReputationPeers,
    (
        SELECT 
            SUM(CASE 
                WHEN v4.VoteTypeId IN (2, 3) THEN 1 
                ELSE 0 
            END) as VoteCount
        FROM Votes v4 
        WHERE v4.UserId = u.Id
        AND v4.CreationDate > DATEADD(week, -4, GETDATE())
    ) as RecentVotes,
    (
        SELECT 
            COUNT(DISTINCT ph4.PostId)
        FROM PostHistory ph4 
        WHERE ph4.UserId = u.Id 
        AND ph4.CreationDate > DATEADD(month, -6, GETDATE())
    ) as RecentEdits,
    (
        SELECT COUNT(DISTINCT p15.Id)
        FROM Users u3
        INNER JOIN Posts p15 ON p15.OwnerUserId = u3.Id
        WHERE u3.Id <> u.Id
        AND u3.Reputation BETWEEN u.Reputation - 500 AND u.Reputation + 500
        AND p15.PostTypeId = 1
    ) as SimilarReputationQuestions,
    (
        SELECT COUNT(DISTINCT p16.Id)
        FROM Users u4
        INNER JOIN Posts p16 ON p16.OwnerUserId = u4.Id
        WHERE u4.Id <> u.Id
        AND u4.Reputation > u.Reputation
        AND p16.PostTypeId = 1
    ) as HigherReputationQuestions,
    (
        SELECT 
            STRING_AGG(
                CASE 
                    WHEN c3.Score > 0 THEN 'Pos' 
                    ELSE 'Neg' 
                END, 
                ', '
            )
        FROM Comments c3 
        WHERE c3.UserId = u.Id
        AND c3.CreationDate > DATEADD(month, -12, GETDATE())
    ) as RecentCommentTypes,
    (
        SELECT 
            COUNT(DISTINCT c4.Id)
        FROM Comments c4 
        WHERE c4.UserId = u.Id 
        AND c4.Score > 5
    ) as HighScoreComments,
    (
        SELECT 
            COUNT(DISTINCT p17.Id)
        FROM Posts p17 
        WHERE p17.OwnerUserId = u.Id 
        AND p17.ViewCount BETWEEN 100 AND 999
    ) as MediumViewCountPosts,
    (
        SELECT 
            COUNT(DISTINCT p18.Id)
        FROM Posts p18 
        WHERE p18.OwnerUserId = u.Id 
        AND p18.ViewCount > 10000
    ) as HighViewCountPosts,
    (
        SELECT 
            COUNT(DISTINCT ps.Id)
        FROM PostLinks ps 
        INNER JOIN Posts p19 ON ps.PostId = p19.Id
        WHERE p19.OwnerUserId = u.Id 
        AND ps.LinkTypeId = 3
    ) as DuplicateLinks,
    (
        SELECT 
            STRING_AGG(
                CAST(COUNT(*) AS VARCHAR) + ' ' + 
                CASE 
                    WHEN ph5.PostHistoryTypeId = 1 THEN 'InitialTitle'
                    WHEN ph5.PostHistoryTypeId = 2 THEN 'InitialBody'
                    WHEN ph5.PostHistoryTypeId = 3 THEN 'InitialTags'
                    ELSE 'Other'
                END,
                ' | '
            )
        FROM PostHistory ph5 
        WHERE ph5.UserId = u.Id
        GROUP BY ph5.PostHistoryTypeId
    ) as HistorySummary,
    (
        SELECT 
            COUNT(*)
        FROM Users u5
        WHERE u5.Reputation > u.Reputation
        AND u5.CreationDate < u.CreationDate
    ) as OlderHigherReputationUsers,
    (
        SELECT 
            COUNT(*)
        FROM Users u6
        WHERE u6.Reputation > u.Reputation
        AND u6.CreationDate > u.CreationDate
    ) as YoungerHigherReputationUsers,
    (
        SELECT 
            COUNT(DISTINCT p20.Id)
        FROM Posts p20 
        WHERE p20.OwnerUserId = u.Id 
        AND p20.CreationDate >= DATEADD(year, -1, GETDATE())
    ) as RecentPosts,
    (
        SELECT 
            COUNT(DISTINCT p21.Id)
        FROM Posts p21 
        WHERE p21.OwnerUserId = u.Id 
        AND p21.CreationDate >= DATEADD(month, -3, GETDATE())
    ) as RecentLastQuarterPosts,
    (
        SELECT 
            COUNT(DISTINCT p22.Id)
        FROM Posts p22 
        WHERE p22.OwnerUserId = u.Id 
        AND p22.AnswerCount > 0
    ) as QuestionWithAnswers,
    (
        SELECT 
            COUNT(DISTINCT p23.Id)
        FROM Posts p23 
        WHERE p23.OwnerUserId = u.Id 
        AND p23.AnswerCount = 0
    ) as QuestionWithNoAnswers,
    (
        SELECT 
            STRING_AGG(
                CASE 
                    WHEN p24.OwnerUserId = u.Id THEN 'Own'
                    ELSE 'Others'
                END, 
                ', '
            )
        FROM Posts p24 
        WHERE p24.Id IN (
            SELECT DISTINCT ph6.PostId 
            FROM PostHistory ph6 
            WHERE ph6.UserId = u.Id
        )
        ORDER BY p24.Id
    ) as PostParticipationTypes,
    (
        SELECT 
            AVG(VoteAverage)
        FROM (
            SELECT 
                AVG(CAST(v5.Score AS FLOAT)) as VoteAverage
            FROM Votes v5 
            WHERE v5.PostId IN (
                SELECT Id FROM Posts WHERE OwnerUserId = u.Id
            )
            GROUP BY v5.PostId
        ) AvgVotes
    ) as AvgVotePerPost,
    (
        SELECT 
            COUNT(*)
        FROM Badges b2 
        WHERE b2.UserId = u.Id
        AND b2.Date >= DATEADD(year, -1, GETDATE())
    ) as RecentBadges,
    (
        SELECT 
            STRING_AGG(
                CONCAT(b3.Name, ' (', b3.Class, ')'), 
                ' | '
            )
        FROM Badges b3 
        WHERE b3.UserId = u.Id
        AND b3.Date >= DATEADD(year, -1, GETDATE())
    ) as RecentBadgeTypes,
    (
        SELECT 
            COUNT(DISTINCT p25.Id)
        FROM Posts p25 
        WHERE p25.OwnerUserId = u.Id 
        AND (
            p25.Body LIKE '%[SQL%' 
            OR p25.Body LIKE '%sql%'
            OR p25.Body LIKE '%[MySQL%' 
            OR p25.Body LIKE '%mysql%'
            OR p25.Body LIKE '%[PostgreSQL%' 
            OR p25.Body LIKE '%postgresql%'
        )
    ) as DatabaseRelatedQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p26 
        WHERE p26.OwnerUserId = u.Id 
        AND p26.Tags LIKE '%[c++]%'
    ) as CPlusPlusQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p27 
        WHERE p27.OwnerUserId = u.Id 
        AND p27.Tags LIKE '%[python]%'
    ) as PythonQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p28 
        WHERE p28.OwnerUserId = u.Id 
        AND p28.Tags LIKE '%[javascript]%'
    ) as JavaScriptQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p29 
        WHERE p29.OwnerUserId = u.Id 
        AND p29.Tags LIKE '%[java]%'
    ) as JavaQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p30 
        WHERE p30.OwnerUserId = u.Id 
        AND p30.Tags LIKE '%[c#]%'
    ) as CSharpQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p31 
        WHERE p31.OwnerUserId = u.Id 
        AND p31.Tags LIKE '%[php]%'
    ) as PHPQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p32 
        WHERE p32.OwnerUserId = u.Id 
        AND p32.Tags LIKE '%[ruby]%'
    ) as RubyQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p33 
        WHERE p33.OwnerUserId = u.Id 
        AND p33.Tags LIKE '%[go]%'
    ) as GoQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p34 
        WHERE p34.OwnerUserId = u.Id 
        AND p34.Tags LIKE '%[rust]%'
    ) as RustQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p35 
        WHERE p35.OwnerUserId = u.Id 
        AND p35.Tags LIKE '%[swift]%'
    ) as SwiftQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p36 
        WHERE p36.OwnerUserId = u.Id 
        AND p36.Tags LIKE '%[kotlin]%'
    ) as KotlinQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p37 
        WHERE p37.OwnerUserId = u.Id 
        AND p37.Tags LIKE '%[scala]%'
    ) as ScalaQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p38 
        WHERE p38.OwnerUserId = u.Id 
        AND p38.Tags LIKE '%[r]%'
    ) as RQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p39 
        WHERE p39.OwnerUserId = u.Id 
        AND p39.Tags LIKE '%[typescript]%'
    ) as TypeScriptQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p40 
        WHERE p40.OwnerUserId = u.Id 
        AND p40.Tags LIKE '%[perl]%'
    ) as PerlQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p41 
        WHERE p41.OwnerUserId = u.Id 
        AND p41.Tags LIKE '%[groovy]%'
    ) as GroovyQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p42 
        WHERE p42.OwnerUserId = u.Id 
        AND p42.Tags LIKE '%[haskell]%'
    ) as HaskellQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p43 
        WHERE p43.OwnerUserId = u.Id 
        AND p43.Tags LIKE '%[elixir]%'
    ) as ElixirQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p44 
        WHERE p44.OwnerUserId = u.Id 
        AND p44.Tags LIKE '%[clojure]%'
    ) as ClojureQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p45 
        WHERE p45.OwnerUserId = u.Id 
        AND p45.Tags LIKE '%[lua]%'
    ) as LuaQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p46 
        WHERE p46.OwnerUserId = u.Id 
        AND p46.Tags LIKE '%[racket]%'
    ) as RacketQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p47 
        WHERE p47.OwnerUserId = u.Id 
        AND p47.Tags LIKE '%[f#]%'
    ) as FSharpQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p48 
        WHERE p48.OwnerUserId = u.Id 
        AND p48.Tags LIKE '%[dart]%'
    ) as DartQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p49 
        WHERE p49.OwnerUserId = u.Id 
        AND p49.Tags LIKE '%[objective-c]%'
    ) as ObjectiveCQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p50 
        WHERE p50.OwnerUserId = u.Id 
        AND p50.Tags LIKE '%[groovy]%'
    ) as GroovyQuestions2,
    (
        SELECT 
            COUNT(*)
        FROM Posts p51 
        WHERE p51.OwnerUserId = u.Id 
        AND p51.Tags LIKE '%[bash]%'
    ) as BashQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p52 
        WHERE p52.OwnerUserId = u.Id 
        AND p52.Tags LIKE '%[powershell]%'
    ) as PowerShellQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p53 
        WHERE p53.OwnerUserId = u.Id 
        AND p53.Tags LIKE '%[sql]%'
    ) as SQLQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p54 
        WHERE p54.OwnerUserId = u.Id 
        AND p54.Tags LIKE '%[plsql]%'
    ) as PLSQLQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p55 
        WHERE p55.OwnerUserId = u.Id 
        AND p55.Tags LIKE '%[t-sql]%'
    ) as TSQLQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p56 
        WHERE p56.OwnerUserId = u.Id 
        AND p56.Tags LIKE '%[mysql]%'
    ) as MySQLQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p57 
        WHERE p57.OwnerUserId = u.Id 
        AND p57.Tags LIKE '%[postgres]%'
    ) as PostgresQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p58 
        WHERE p58.OwnerUserId = u.Id 
        AND p58.Tags LIKE '%[oracle]%'
    ) as OracleQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p59 
        WHERE p59.OwnerUserId = u.Id 
        AND p59.Tags LIKE '%[mssql]%'
    ) as MSSQLQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p60 
        WHERE p60.OwnerUserId = u.Id 
        AND p60.Tags LIKE '%[sqlite]%'
    ) as SQLiteQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p61 
        WHERE p61.OwnerUserId = u.Id 
        AND p61.Tags LIKE '%[mongodb]%'
    ) as MongoDBQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p62 
        WHERE p62.OwnerUserId = u.Id 
        AND p62.Tags LIKE '%[redis]%'
    ) as RedisQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p63 
        WHERE p63.OwnerUserId = u.Id 
        AND p63.Tags LIKE '%[elasticsearch]%'
    ) as ElasticSearchQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p64 
        WHERE p64.OwnerUserId = u.Id 
        AND p64.Tags LIKE '%[cassandra]%'
    ) as CassandraQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p65 
        WHERE p65.OwnerUserId = u.Id 
        AND p65.Tags LIKE '%[hadoop]%'
    ) as HadoopQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p66 
        WHERE p66.OwnerUserId = u.Id 
        AND p66.Tags LIKE '%[spark]%'
    ) as SparkQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p67 
        WHERE p67.OwnerUserId = u.Id 
        AND p67.Tags LIKE '%[kafka]%'
    ) as KafkaQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p68 
        WHERE p68.OwnerUserId = u.Id 
        AND p68.Tags LIKE '%[hazelcast]%'
    ) as HazelcastQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p69 
        WHERE p69.OwnerUserId = u.Id 
        AND p69.Tags LIKE '%[rabbitmq]%'
    ) as RabbitMQQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p70 
        WHERE p70.OwnerUserId = u.Id 
        AND p70.Tags LIKE '%[activemq]%'
    ) as ActiveMQQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p71 
        WHERE p71.OwnerUserId = u.Id 
        AND p71.Tags LIKE '%[jenkins]%'
    ) as JenkinsQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p72 
        WHERE p72.OwnerUserId = u.Id 
        AND p72.Tags LIKE '%[docker]%'
    ) as DockerQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p73 
        WHERE p73.OwnerUserId = u.Id 
        AND p73.Tags LIKE '%[kubernetes]%'
    ) as KubernetesQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p74 
        WHERE p74.OwnerUserId = u.Id 
        AND p74.Tags LIKE '%[aws]%'
    ) as AWSQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p75 
        WHERE p75.OwnerUserId = u.Id 
        AND p75.Tags LIKE '%[azure]%'
    ) as AzureQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p76 
        WHERE p76.OwnerUserId = u.Id 
        AND p76.Tags LIKE '%[gcp]%'
    ) as GCPQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p77 
        WHERE p77.OwnerUserId = u.Id 
        AND p77.Tags LIKE '%[terraform]%'
    ) as TerraformQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p78 
        WHERE p78.OwnerUserId = u.Id 
        AND p78.Tags LIKE '%[ansible]%'
    ) as AnsibleQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p79 
        WHERE p79.OwnerUserId = u.Id 
        AND p79.Tags LIKE '%[chef]%'
    ) as ChefQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p80 
        WHERE p80.OwnerUserId = u.Id 
        AND p80.Tags LIKE '%[puppet]%'
    ) as PuppetQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p81 
        WHERE p81.OwnerUserId = u.Id 
        AND p81.Tags LIKE '%[git]%'
    ) as GitQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p82 
        WHERE p82.OwnerUserId = u.Id 
        AND p82.Tags LIKE '%[github]%'
    ) as GitHubQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p83 
        WHERE p83.OwnerUserId = u.Id 
        AND p83.Tags LIKE '%[gitlab]%'
    ) as GitLabQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p84 
        WHERE p84.OwnerUserId = u.Id 
        AND p84.Tags LIKE '%[bitbucket]%'
    ) as BitbucketQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p85 
        WHERE p85.OwnerUserId = u.Id 
        AND p85.Tags LIKE '%[jenkins]%'
    ) as JenkinsQuestions2,
    (
        SELECT 
            COUNT(*)
        FROM Posts p86 
        WHERE p86.OwnerUserId = u.Id 
        AND p86.Tags LIKE '%[travis]%'
    ) as TravisQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p87 
        WHERE p87.OwnerUserId = u.Id 
        AND p87.Tags LIKE '%[circleci]%'
    ) as CircleCIQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p88 
        WHERE p88.OwnerUserId = u.Id 
        AND p88.Tags LIKE '%[azure-devops]%'
    ) as AzureDevOpsQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p89 
        WHERE p89.OwnerUserId = u.Id 
        AND p89.Tags LIKE '%[teamcity]%'
    ) as TeamCityQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p90 
        WHERE p90.OwnerUserId = u.Id 
        AND p90.Tags LIKE '%[bamboo]%'
    ) as BambooQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p91 
        WHERE p91.OwnerUserId = u.Id 
        AND p91.Tags LIKE '%[buildkite]%'
    ) as BuildkiteQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p92 
        WHERE p92.OwnerUserId = u.Id 
        AND p92.Tags LIKE '%[argocd]%'
    ) as ArgoCDQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p93 
        WHERE p93.OwnerUserId = u.Id 
        AND p93.Tags LIKE '%[spinnaker]%'
    ) as SpinnakerQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p94 
        WHERE p94.OwnerUserId = u.Id 
        AND p94.Tags LIKE '%[concourse]%'
    ) as ConcourseQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p95 
        WHERE p95.OwnerUserId = u.Id 
        AND p95.Tags LIKE '%[tekton]%'
    ) as TektonQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p96 
        WHERE p96.OwnerUserId = u.Id 
        AND p96.Tags LIKE '%[drone]%'
    ) as DroneQuestions,
    (
        SELECT 
            COUNT(*)
        FROM Posts p97 
        WHERE p97.OwnerUserId = u.Id 
        AND p97.Tags LIKE '%[wercker]%'
    ) as WerckerQuestions
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE u.Reputation > 0
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.Location
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;