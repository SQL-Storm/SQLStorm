-- {"query": "3057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1111} 
WITH RECURSIVE PostAnswerHierarchy AS (
    SELECT 
        p.Id AS QuestionId,
        a.Id AS AnswerId,
        p.CreationDate AS QuestionCreationDate,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS Rank
    FROM 
        Posts p
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
        LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1
),
TopAnswers AS (
    SELECT 
        QuestionId,
        AnswerId,
        OwnerUserId,
        OwnerDisplayName,
        AnswerScore
    FROM 
        PostAnswerHierarchy
    WHERE 
        Rank = 1
),
RecentQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.ViewCount,
        p.Score AS QuestionScore,
        COUNT(a.AnswerId) AS TotalAnswers
    FROM 
        Posts p
        LEFT JOIN TopAnswers a ON p.Id = a.QuestionId
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND
        p.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Tags, p.ViewCount, p.Score
),
PopularQuestions AS (
    SELECT 
        QuestionId,
        Title,
        CreationDate,
        Tags,
        ViewCount,
        QuestionScore,
        TotalAnswers,
        COUNT(CASE WHEN OwnerUserId IS NULL THEN 1 END) FILTER (WHERE a.OwnerUserId IS NULL) AS AnonymousAnswers,
        COUNT(CASE WHEN OwnerUserId IS NOT NULL THEN 1 END) AS RegisteredAnswers
    FROM 
        RecentQuestions rq
        LEFT JOIN TopAnswers a ON rq.QuestionId = a.QuestionId
    GROUP BY 
        rq.QuestionId, rq.Title, rq.CreationDate, rq.Tags, rq.ViewCount, rq.QuestionScore, rq.TotalAnswers
),
CommentStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.Score) FILTER (WHERE c.UserId IS NULL) AS MaxAnonymousCommentScore,
        BOOL_AND(c.UserId IS NOT NULL) AS AllCommentsRegistered
    FROM 
        Posts p
        LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id
)
SELECT 
    pq.QuestionId,
    pq.Title,
    pq.CreationDate,
    string_agg(DISTINCT unnest(string_to_array(substring(pq.Tags, 2, length(pq.Tags)-2), '><')), ',') AS UniqueTags,
    pq.ViewCount,
    pq.QuestionScore,
    pq.TotalAnswers,
    pq.AnonymousAnswers,
    pq.RegisteredAnswers,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.MaxAnonymousCommentScore,
    cs.AllCommentsRegistered,
    TRUE AS HasPopularAnswer,
    COALESCE(vote_stats.VoteCount, 0) AS TotalVotes,
    CASE WHEN u.Reputation >= 1000 THEN TRUE ELSE FALSE END AS IsHighReputation
FROM 
    PopularQuestions pq
    LEFT JOIN CommentStats cs ON pq.QuestionId = cs.PostId
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS VoteCount
        FROM 
            Votes
        GROUP BY 
            PostId
    ) vote_stats ON pq.QuestionId = vote_stats.PostId
    LEFT JOIN Users u ON u.Id = pq.OwnerUserId
WHERE 
    pq.ViewCount > 100 AND
    pq.TotalAnswers > 2 AND
    (pq.AnonymousAnswers + pq.RegisteredAnswers) > 2
UNION ALL
SELECT 
    pq.QuestionId,
    pq.Title,
    pq.CreationDate,
    string_agg(DISTINCT unnest(string_to_array(substring(pq.Tags, 2, length(pq.Tags)-2), '><')), ',') AS UniqueTags,
    pq.ViewCount,
    pq.QuestionScore,
    pq.TotalAnswers,
    pq.AnonymousAnswers,
    pq.RegisteredAnswers,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.MaxAnonymousCommentScore,
    cs.AllCommentsRegistered,
    FALSE AS HasPopularAnswer,
    COALESCE(vote_stats.VoteCount, 0) AS TotalVotes,
    FALSE AS IsHighReputation
FROM 
    PopularQuestions pq
    LEFT JOIN CommentStats cs ON pq.QuestionId = cs.PostId
    LEFT JOIN (
        SELECT 
            PostId,
            COUNT(*) AS VoteCount
        FROM 
            Votes
        GROUP BY 
            PostId
    ) vote_stats ON pq.QuestionId = vote_stats.PostId
    LEFT JOIN Users u ON u.Id = pq.OwnerUserId
WHERE 
    pq.ViewCount < 50 AND
    pq.TotalAnswers = 0
ORDER BY 
    pq.CreationDate DESC
LIMIT 50;