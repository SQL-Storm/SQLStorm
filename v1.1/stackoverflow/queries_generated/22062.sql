-- {"query": "22062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1379} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.WebsiteUrl, 'No Website') AS Website,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(LENGTH(p.Body)) AS AvgBodyLength,
        AVG(LENGTH(p.Title)) AS AvgTitleLength,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.WebsiteUrl
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(Name, ', ' ORDER BY Date DESC) AS RecentBadges
    FROM Badges
    WHERE Date >= '2020-01-01'
    GROUP BY UserId
),
VoteStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        COUNT(CASE WHEN VoteTypeId IN (4,5,6,7) THEN 1 END) AS OtherVotes
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
TopUsers AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.AvgBodyLength,
        us.AvgTitleLength,
        us.AcceptedQuestions,
        COALESCE(bs.TotalBadges, 0) AS TotalBadges,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        bs.RecentBadges,
        COALESCE(vs.UpVotesGiven, 0) AS UpVotesGiven,
        COALESCE(vs.DownVotesGiven, 0) AS DownVotesGiven,
        COALESCE(vs.OtherVotes, 0) AS OtherVotes,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS ReputationRank,
        PERCENT_RANK() OVER (ORDER BY us.TotalScore DESC) AS ScorePercentile
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON us.Id = bs.UserId
    LEFT JOIN VoteStats vs ON us.Id = vs.UserId
    WHERE us.QuestionCount > 0 OR us.AnswerCount > 0
),
ActivitySummary AS (
    SELECT 
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.TotalScore,
        tu.TotalBadges,
        tu.UpVotesGiven,
        tu.DownVotesGiven,
        tu.ScorePercentile,
        CASE 
            WHEN tu.TotalBadges > 10 THEN 'High Badge User'
            WHEN tu.TotalBadges BETWEEN 5 AND 10 THEN 'Medium Badge User'
            ELSE 'Low Badge User'
        END AS BadgeCategory
    FROM TopUsers tu
    WHERE tu.ReputationRank <= 1000
),
PostTagStats AS (
    SELECT 
        p.OwnerUserId,
        t.TagName,
        COUNT(*) AS TagPostCount,
        AVG(p.Score) AS AvgScorePerTag
    FROM Posts p
    CROSS JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    JOIN Tags t2 ON t.TagName = t2.TagName
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
ComplexQuery AS (
    SELECT 
        asu.Id,
        asu.DisplayName,
        asu.Reputation,
        asu.TotalScore,
        asu.TotalBadges,
        asu.ScorePercentile,
        pts.TagName AS TopTag,
        pts.AvgScorePerTag,
        CASE 
            WHEN asu.ScorePercentile > 0.9 THEN 'Top 10%'
            WHEN asu.ScorePercentile > 0.5 THEN 'Top 50%'
            ELSE 'Bottom 50%'
        END AS ScoreGroup,
        LEAD(asu.Reputation) OVER (ORDER BY asu.Reputation DESC) AS NextUserRep,
        LAG(asu.Reputation) OVER (ORDER BY asu.Reputation DESC) AS PrevUserRep
    FROM ActivitySummary asu
    LEFT JOIN (
        SELECT 
            OwnerUserId,
            TagName,
            AvgScorePerTag,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagPostCount DESC, AvgScorePerTag DESC) AS rn
        FROM PostTagStats
    ) pts ON asu.Id = pts.OwnerUserId AND pts.rn = 1
    WHERE asu.TotalScore > (
        SELECT AVG(TotalScore) 
        FROM ActivitySummary 
        WHERE BadgeCategory = 'High Badge User'
    ) OR asu.Id IN (
        SELECT Id 
        FROM TopUsers 
        WHERE GoldBadges > 0
    )
    ORDER BY asu.ScorePercentile DESC, asu.Reputation DESC
)
SELECT * FROM ComplexQuery
WHERE TopTag IS NOT NULL OR ScoreGroup = 'Top 10%'
UNION ALL
SELECT 
    NULL AS Id,
    'Total Users' AS DisplayName,
    COUNT(*) AS Reputation,
    SUM(TotalScore) AS TotalScore,
    SUM(TotalBadges) AS TotalBadges,
    AVG(ScorePercentile) AS ScorePercentile,
    NULL AS TopTag,
    AVG(AvgScorePerTag) AS AvgScorePerTag,
    'Aggregate' AS ScoreGroup,
    NULL AS NextUserRep,
    NULL AS PrevUserRep
FROM ComplexQuery;