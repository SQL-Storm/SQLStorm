-- {"query": "3340.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2952} 

WITH 
RecentQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        COALESCE(p.FavoriteCount,0) AS FavCnt,
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS LastVoteDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
TagAggregates AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)               AS QuestionCnt,
        AVG(p.Score)              AS AvgScore,
        SUM(p.ViewCount)          AS TotalViews
    FROM Tags t
    JOIN Posts p ON p.Tags ILIKE '%'||t.TagName||'%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
UserStats AS (
    SELECT 
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS RowNum
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        UpVotesGiven,
        DownVotesGiven,
        QuestionsAsked,
        AnswersProvided,
        (UpVotesGiven - DownVotesGiven)                AS NetVotes,
        ROW_NUMBER() OVER (ORDER BY (UpVotesGiven + AnswersProvided) DESC) AS Rank
    FROM UserStats
    WHERE Reputation > 1000
)
SELECT
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.FavCnt,
    COALESCE(rq.Score * rq.ViewCount / NULLIF(rq.AnswerCount,0),0) AS PerformanceScore,
    COALESCE(ta.AvgScore,0)                                   AS TagAvgScore,
    tu.DisplayName                                            AS OwnerName,
    tu.Reputation                                             AS OwnerReputation,
    tu.Rank                                                   AS OwnerRank,
    CASE 
        WHEN rq.LastVoteDate IS NULL      THEN 'NoVotes'
        WHEN rq.LastVoteDate < rq.CreationDate THEN 'OldVotes'
        ELSE 'RecentVotes'
    END                                                       AS VoteRecency,
    STRING_AGG(DISTINCT ta.TagName, ',') FILTER (WHERE ta.TagName IS NOT NULL) AS RelatedTags
FROM RecentQuestions rq
LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM Tags t
    WHERE rq.Tags ILIKE '%'||t.TagName||'%'
) t ON true
LEFT JOIN TagAggregates ta ON ta.TagName = t.TagName
LEFT JOIN TopActiveUsers tu ON tu.UserId = rq.OwnerUserId
GROUP BY 
    rq.Id, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount,
    rq.FavCnt, rq.LastVoteDate, ta.AvgScore, tu.DisplayName, tu.Reputation, tu.Rank

UNION ALL

SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    COALESCE(p.FavoriteCount,0)                               AS FavCnt,
    COALESCE(p.Score * p.ViewCount / NULLIF(p.AnswerCount,0),0) AS PerformanceScore,
    NULL                                                      AS TagAvgScore,
    u.DisplayName                                            AS OwnerName,
    u.Reputation                                             AS OwnerReputation,
    NULL                                                     AS OwnerRank,
    'Legacy'                                                 AS VoteRecency,
    NULL                                                     AS RelatedTags
FROM Posts p
JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.CreationDate < CURRENT_DATE - INTERVAL '365 days'
  AND NOT EXISTS (SELECT 1 FROM RecentQuestions rq WHERE rq.Id = p.Id)

ORDER BY CreationDate DESC
LIMIT 100;
