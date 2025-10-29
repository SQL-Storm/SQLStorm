-- {"query": "7267.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 7702} 
WITH UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 5000 THEN 'Pro'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserLevel,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostStats AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        COALESCE(p.ParentId, 0) as ParentId,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        CASE WHEN p.ParentId IS NOT NULL THEN 'Answer' ELSE 'Question' END as PostType,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId IN (3) THEN 1 ELSE 0 END), 0) as NetVotes,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as OverallRank,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1,2) 
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.PostTypeId, p.AnswerCount, p.CommentCount, p.Tags, p.ParentId, p.AcceptedAnswerId, p.ClosedDate
),
UserPostSummary AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.QuestionCount,
        ua.AnswerCount,
        CASE WHEN ua.QuestionCount > 0 THEN CAST(ua.AnswerCount AS FLOAT) / CAST(ua.QuestionCount AS FLOAT) ELSE 0 END as AnswerRatio,
        CASE WHEN ua.Reputation > 0 THEN CAST(ua.PostCount AS FLOAT) / CAST(ua.Reputation AS FLOAT) ELSE 0 END as PostRepRatio
    FROM UserActivity ua
    WHERE ua.PostCount > 0
),
TopPosts AS (
    SELECT TOP 100 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.PostType,
        ps.OwnerUserId,
        ps.DaysOpen,
        ps.NetVotes,
        ps.ScoreRank,
        ps.OverallRank,
        ps.AvgScoreByType,
        ps.Tags,
        ps.CommentCount,
        ps.HistoryCount
    FROM PostStats ps
    WHERE ps.Score >= 100
    ORDER BY ps.Score DESC, ps.ViewCount DESC
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%'), 0) as RelatedPosts,
        (SELECT AVG(ps.Score) FROM Posts ps WHERE ps.Tags LIKE '%' + t.TagName + '%') as AvgScore,
        (SELECT MAX(ps.Score) FROM Posts ps WHERE ps.Tags LIKE '%' + t.TagName + '%') as MaxScore
    FROM Tags t
    WHERE t.Count > 100
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalUserCount,
    (SELECT COUNT(*) FROM TopPosts) as TopPostCount,
    (SELECT COUNT(*) FROM TagAnalysis) as TagAnalysisCount,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) as AnswerCount,
    (SELECT AVG(Reputation) FROM UserActivity) as AvgReputation,
    (SELECT AVG(Score) FROM TopPosts) as AvgTopPostScore,
    (SELECT AVG(Count) FROM TagAnalysis) as AvgTagCount,
    (
        SELECT COUNT(*)
        FROM Posts p1
        INNER JOIN Posts p2 ON p1.Id = p2.ParentId
        WHERE p1.PostTypeId = 1 AND p2.PostTypeId = 2
    ) as QuestionAnswerRelationships,
    (
        SELECT COUNT(*)
        FROM (
            SELECT DISTINCT UserId FROM Users WHERE Id IN (
                SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 1
                UNION
                SELECT DISTINCT LastEditorUserId FROM Posts WHERE LastEditorUserId IS NOT NULL
                UNION
                SELECT DISTINCT UserId FROM Comments
                UNION
                SELECT DISTINCT UserId FROM Badges
                UNION
                SELECT DISTINCT UserId FROM Votes
            )
        ) as UserCount
    ) as ActiveUserCount,
    (
        SELECT TOP 1 Title 
        FROM TopPosts 
        ORDER BY Score DESC, ViewCount DESC
    ) as HighestRatedPost,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags IS NOT NULL 
        AND p.Tags != '' 
        AND p.PostTypeId = 1
    ) as TaggedQuestionCount,
    (
        SELECT MAX(Reputation) 
        FROM Users 
        WHERE Reputation > 0
    ) as MaxUserReputation,
    (
        SELECT AVG(NetVotes) 
        FROM PostStats 
        WHERE NetVotes IS NOT NULL
    ) as AvgNetVotes,
    (
        SELECT COUNT(*) 
        FROM Posts 
        WHERE CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)
    ) as RecentPostCount,
    (
        SELECT COUNT(*) 
        FROM Users 
        WHERE LastAccessDate >= DATEADD(DAY, -7, CURRENT_TIMESTAMP)
    ) as ActiveUsersWeek,
    (
        SELECT COUNT(*) 
        FROM Posts 
        WHERE Score < 0 
        AND OwnerUserId IS NOT NULL
    ) as NegativeScoredPosts,
    (
        SELECT COUNT(*) 
        FROM Posts 
        WHERE ViewCount > 10000
    ) as HighlyViewedPosts,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.OwnerUserId, COUNT(*) as PostCount
            FROM Posts p
            WHERE p.PostTypeId = 1
            GROUP BY p.OwnerUserId
            HAVING COUNT(*) >= 100
        ) high_posters
    ) as HighVolumeQuestioners,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.OwnerUserId, COUNT(*) as AnswerCount
            FROM Posts p
            WHERE p.PostTypeId = 2
            GROUP BY p.OwnerUserId
            HAVING COUNT(*) >= 50
        ) high_answerers
    ) as HighVolumeAnswerers,
    (
        SELECT AVG(ABS(CAST(ps.Score AS FLOAT) - CAST(ps.AvgScoreByType AS FLOAT))) 
        FROM PostStats ps
    ) as ScoreDeviationFromMean,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT DISTINCT p.OwnerUserId 
            FROM Posts p 
            WHERE p.PostTypeId = 1 
            GROUP BY p.OwnerUserId
            HAVING COUNT(*) > 10
        ) multiple_questioners
    ) as MultipleQuestioners,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p.OwnerUserId 
            FROM Posts p 
            WHERE p.PostTypeId = 1 
            GROUP BY p.OwnerUserId
            HAVING COUNT(*) > 0
        ) question_authors
    ) as AllQuestionAuthors,
    (
        SELECT COUNT(*) 
        FROM Tags t
        WHERE t.TagName IN (
            SELECT Value FROM STRING_SPLIT((
                SELECT Tags FROM Posts WHERE PostTypeId = 1 AND Tags IS NOT NULL AND Tags != ''
                ORDER BY CreationDate DESC
                LIMIT 100
            ), '><')
        )
    ) as TagFrequency,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<c%>%' 
        AND p.PostTypeId = 1
    ) as CRelatedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<javascript>%' 
        AND p.PostTypeId = 1
    ) as JavaScriptQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<python>%' 
        AND p.PostTypeId = 1
    ) as PythonQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<java>%' 
        AND p.PostTypeId = 1
    ) as JavaQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<php>%' 
        AND p.PostTypeId = 1
    ) as PHPQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<c++>%' 
        AND p.PostTypeId = 1
    ) as CPlusPlusQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<ruby>%' 
        AND p.PostTypeId = 1
    ) as RubyQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<go>%' 
        AND p.PostTypeId = 1
    ) as GoQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<rust>%' 
        AND p.PostTypeId = 1
    ) as RustQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<swift>%' 
        AND p.PostTypeId = 1
    ) as SwiftQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags LIKE '%<kotlin>%' 
        AND p.PostTypeId = 1
    ) as KotlinQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%help%' 
        AND p.PostTypeId = 1
    ) as HelpQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%best%' 
        AND p.PostTypeId = 1
    ) as BestQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%tutorial%' 
        AND p.PostTypeId = 1
    ) as TutorialQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%example%' 
        AND p.PostTypeId = 1
    ) as ExampleQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%solution%' 
        AND p.PostTypeId = 1
    ) as SolutionQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%problem%' 
        AND p.PostTypeId = 1
    ) as ProblemQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%answer%' 
        AND p.PostTypeId = 1
    ) as AnswerQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%question%' 
        AND p.PostTypeId = 1
    ) as QuestionQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%code%' 
        AND p.PostTypeId = 1
    ) as CodeQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%function%' 
        AND p.PostTypeId = 1
    ) as FunctionQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%class%' 
        AND p.PostTypeId = 1
    ) as ClassQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%method%' 
        AND p.PostTypeId = 1
    ) as MethodQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%variable%' 
        AND p.PostTypeId = 1
    ) as VariableQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%array%' 
        AND p.PostTypeId = 1
    ) as ArrayQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%string%' 
        AND p.PostTypeId = 1
    ) as StringQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%loop%' 
        AND p.PostTypeId = 1
    ) as LoopQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%condition%' 
        AND p.PostTypeId = 1
    ) as ConditionQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%algorithm%' 
        AND p.PostTypeId = 1
    ) as AlgorithmQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%data%' 
        AND p.PostTypeId = 1
    ) as DataQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%database%' 
        AND p.PostTypeId = 1
    ) as DatabaseQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%network%' 
        AND p.PostTypeId = 1
    ) as NetworkQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%security%' 
        AND p.PostTypeId = 1
    ) as SecurityQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%performance%' 
        AND p.PostTypeId = 1
    ) as PerformanceQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%design%' 
        AND p.PostTypeId = 1
    ) as DesignQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%architecture%' 
        AND p.PostTypeId = 1
    ) as ArchitectureQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%scalability%' 
        AND p.PostTypeId = 1
    ) as ScalabilityQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%optimization%' 
        AND p.PostTypeId = 1
    ) as OptimizationQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%debugging%' 
        AND p.PostTypeId = 1
    ) as DebuggingQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%testing%' 
        AND p.PostTypeId = 1
    ) as TestingQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%framework%' 
        AND p.PostTypeId = 1
    ) as FrameworkQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%library%' 
        AND p.PostTypeId = 1
    ) as LibraryQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%tool%' 
        AND p.PostTypeId = 1
    ) as ToolQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%platform%' 
        AND p.PostTypeId = 1
    ) as PlatformQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%environment%' 
        AND p.PostTypeId = 1
    ) as EnvironmentQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%deployment%' 
        AND p.PostTypeId = 1
    ) as DeploymentQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%integration%' 
        AND p.PostTypeId = 1
    ) as IntegrationQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%api%' 
        AND p.PostTypeId = 1
    ) as APIQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%rest%' 
        AND p.PostTypeId = 1
    ) as RESTQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%graphql%' 
        AND p.PostTypeId = 1
    ) as GraphQLQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%web%' 
        AND p.PostTypeId = 1
    ) as WebQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%mobile%' 
        AND p.PostTypeId = 1
    ) as MobileQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%desktop%' 
        AND p.PostTypeId = 1
    ) as DesktopQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%cloud%' 
        AND p.PostTypeId = 1
    ) as CloudQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%devops%' 
        AND p.PostTypeId = 1
    ) as DevOpsQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%ci%' 
        AND p.PostTypeId = 1
    ) as CIQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%cd%' 
        AND p.PostTypeId = 1
    ) as CDQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%agile%' 
        AND p.PostTypeId = 1
    ) as AgileQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%scrum%' 
        AND p.PostTypeId = 1
    ) as ScrumQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%kanban%' 
        AND p.PostTypeId = 1
    ) as KanbanQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%project%' 
        AND p.PostTypeId = 1
    ) as ProjectQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%planning%' 
        AND p.PostTypeId = 1
    ) as PlanningQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%estimation%' 
        AND p.PostTypeId = 1
    ) as EstimationQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%tracking%' 
        AND p.PostTypeId = 1
    ) as TrackingQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%monitoring%' 
        AND p.PostTypeId = 1
    ) as MonitoringQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%logging%' 
        AND p.PostTypeId = 1
    ) as LoggingQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%alerting%' 
        AND p.PostTypeId = 1
    ) as AlertingQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%backup%' 
        AND p.PostTypeId = 1
    ) as BackupQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%recovery%' 
        AND p.PostTypeId = 1
    ) as RecoveryQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%migration%' 
        AND p.PostTypeId = 1
    ) as MigrationQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%upgrade%' 
        AND p.PostTypeId = 1
    ) as UpgradeQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%compatibility%' 
        AND p.PostTypeId = 1
    ) as CompatibilityQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%upgrade%' 
        AND p.PostTypeId = 1
    ) as UpgradeQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%migration%' 
        AND p.PostTypeId = 1
    ) as MigrationQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%database%' 
        AND p.PostTypeId = 1
    ) as DatabaseQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%sql%' 
        AND p.PostTypeId = 1
    ) as SQLQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%nosql%' 
        AND p.PostTypeId = 1
    ) as NoSQLQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%mongodb%' 
        AND p.PostTypeId = 1
    ) as MongoDBQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%postgresql%' 
        AND p.PostTypeId = 1
    ) as PostgreSQLQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%mysql%' 
        AND p.PostTypeId = 1
    ) as MySQLQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%oracle%' 
        AND p.PostTypeId = 1
    ) as OracleQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%sqlserver%' 
        AND p.PostTypeId = 1
    ) as SQLServerQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%redis%' 
        AND p.PostTypeId = 1
    ) as RedisQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%elasticsearch%' 
        AND p.PostTypeId = 1
    ) as ElasticsearchQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%kafka%' 
        AND p.PostTypeId = 1
    ) as KafkaQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%docker%' 
        AND p.PostTypeId = 1
    ) as DockerQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%kubernetes%' 
        AND p.PostTypeId = 1
    ) as KubernetesQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%aws%' 
        AND p.PostTypeId = 1
    ) as AWSQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%azure%' 
        AND p.PostTypeId = 1
    ) as AzureQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%gcp%' 
        AND p.PostTypeId = 1
    ) as GCPQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%linux%' 
        AND p.PostTypeId = 1
    ) as LinuxQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%windows%' 
        AND p.PostTypeId = 1
    ) as WindowsQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%macos%' 
        AND p.PostTypeId = 1
    ) as MacOSQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%ios%' 
        AND p.PostTypeId = 1
    ) as iOSQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%android%' 
        AND p.PostTypeId = 1
    ) as AndroidQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%react%' 
        AND p.PostTypeId = 1
    ) as ReactQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%vue%' 
        AND p.PostTypeId = 1
    ) as VueQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%angular%' 
        AND p.PostTypeId = 1
    ) as AngularQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%ember%' 
        AND p.PostTypeId = 1
    ) as EmberQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%backbone%' 
        AND p.PostTypeId = 1
    ) as BackboneQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%wordpress%' 
        AND p.PostTypeId = 1
    ) as WordPressQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%drupal%' 
        AND p.PostTypeId = 1
    ) as DrupalQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%joomla%' 
        AND p.PostTypeId = 1
    ) as JoomlaQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%laravel%' 
        AND p.PostTypeId = 1
    ) as LaravelQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%symfony%' 
        AND p.PostTypeId = 1
    ) as SymfonyQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%django%' 
        AND p.PostTypeId = 1
    ) as DjangoQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%flask%' 
        AND p.PostTypeId = 1
    ) as FlaskQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%rails%' 
        AND p.PostTypeId = 1
    ) as RailsQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%spring%' 
        AND p.PostTypeId = 1
    ) as SpringQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%dotnet%' 
        AND p.PostTypeId = 1
    ) as DotNetQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%asp%' 
        AND p.PostTypeId = 1
    ) as ASPQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%net%' 
        AND p.PostTypeId = 1
    ) as NetQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%c#' 
        AND p.PostTypeId = 1
    ) as CSharpQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%f#' 
        AND p.PostTypeId = 1
    ) as FSharpQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%vb%' 
        AND p.PostTypeId = 1
    ) as VBQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%typescript%' 
        AND p.PostTypeId = 1
    ) as TypeScriptQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%javascript%' 
        AND p.PostTypeId = 1
    ) as JavaScriptQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%node%' 
        AND p.PostTypeId = 1
    ) as NodeQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%python%' 
        AND p.PostTypeId = 1
    ) as PythonQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%java%' 
        AND p.PostTypeId = 1
    ) as JavaQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%php%' 
        AND p.PostTypeId = 1
    ) as PHPQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%c++%' 
        AND p.PostTypeId = 1
    ) as CPlusPlusQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%ruby%' 
        AND p.PostTypeId = 1
    ) as RubyQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%go%' 
        AND p.PostTypeId = 1
    ) as GoQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%rust%' 
        AND p.PostTypeId = 1
    ) as RustQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%swift%' 
        AND p.PostTypeId = 1
    ) as SwiftQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%kotlin%' 
        AND p.PostTypeId = 1
    ) as KotlinQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%r%' 
        AND p.PostTypeId = 1
    ) as RQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%scala%' 
        AND p.PostTypeId = 1
    ) as ScalaQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%groovy%' 
        AND p.PostTypeId = 1
    ) as GroovyQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%perl%' 
        AND p.PostTypeId = 1
    ) as PerlQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%bash%' 
        AND p.PostTypeId = 1
    ) as BashQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%powershell%' 
        AND p.PostTypeId = 1
    ) as PowerShellQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%shell%' 
        AND p.PostTypeId = 1
    ) as ShellQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%ansible%' 
        AND p.PostTypeId = 1
    ) as AnsibleQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%chef%' 
        AND p.PostTypeId = 1
    ) as ChefQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%puppet%' 
        AND p.PostTypeId = 1
    ) as PuppetQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%salt%' 
        AND p.PostTypeId = 1
    ) as SaltQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%terraform%' 
        AND p.PostTypeId = 1
    ) as TerraformQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%vagrant%' 
        AND p.PostTypeId = 1
    ) as VagrantQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%jenkins%' 
        AND p.PostTypeId = 1
    ) as JenkinsQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%git%' 
        AND p.PostTypeId = 1
    ) as GitQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%svn%' 
        AND p.PostTypeId = 1
    ) as SVNQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%mercurial%' 
        AND p.PostTypeId = 1
    ) as MercurialQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%github%' 
        AND p.PostTypeId = 1
    ) as GitHubQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%gitlab%' 
        AND p.PostTypeId = 1
    ) as GitLabQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%bitbucket%' 
        AND p.PostTypeId = 1
    ) as BitBucketQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%circle%' 
        AND p.PostTypeId = 1
    ) as CircleQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%travis%' 
        AND p.PostTypeId = 1
    ) as TravisQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%jenkins%' 
        AND p.PostTypeId = 1
    ) as JenkinsQuestions2,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title LIKE '%github%' 
        AND p.PostTypeId = 1
    ) as GitHubQuestions2
FROM UserActivity ua
RIGHT JOIN PostStats ps ON ua.UserId = ps.OwnerUserId
LEFT JOIN UserPostSummary ups ON ua.UserId = ups.UserId
LEFT JOIN TopPosts tp ON ps.PostId = tp.PostId
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT Value FROM STRING_SPLIT(
        ps.Tags, '><'
    ) WHERE Value IS NOT NULL AND Value != ''
)
WHERE ua.UserId IS NOT NULL
GROUP BY ua.UserId, ps.OwnerUserId, ups.UserId, tp.PostId, ta.TagName
HAVING COUNT(*) >= 1
ORDER BY ua.UserId ASC, ps.Score DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;