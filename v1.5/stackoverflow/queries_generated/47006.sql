-- {"query": "47006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 13764, "output_tokens": 11902} 

WITH RECURSIVE TagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        1 AS Level
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    INNER JOIN Posts pt ON pt.Id = p.Id AND pt.PostTypeId = 1
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        COUNT(DISTINCT p2.Id) AS QuestionCount,
        AVG(p2.Score) AS AvgScore,
        th.Level + 1
    FROM TagHierarchy th
    INNER JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    INNER JOIN Posts p2 ON p2.Id != p1.Id 
        AND p2.PostTypeId = 1
        AND p2.CreationDate BETWEEN p1.CreationDate - INTERVAL '30 days' AND p1.CreationDate + INTERVAL '30 days'
    INNER JOIN Tags t2 ON p2.Tags LIKE '%<' || t2.TagName || '>%' 
        AND t2.Id != th.Id
    WHERE th.Level < 3
    GROUP BY t2.Id, t2.TagName, th.Level
),
UserExpertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) AS AcceptedAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STDDEV(p.Score) AS ScoreStdDev,
        COUNT(DISTINCT b.Id) AS RelatedBadges,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Name LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 5000
        AND p.Score > 0
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
PostEvolution AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS WasClosedReopened,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) AS HistoryTypes,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate)))/3600 AS EditSpanHours
    FROM Posts p
    INNER JOIN PostHistory ph ON ph.PostId = p.Id
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE p.PostTypeId = 1
        AND p.Score >= 50
        AND p.ViewCount > 10000
    GROUP BY p.Id, p.Title, p.CreationDate
),
VotingPatterns AS (
    SELECT 
        DATE_TRUNC('month', v.CreationDate) AS VoteMonth,
        vt.Name AS VoteType,
        COUNT(*) AS VoteCount,
        COUNT(DISTINCT v.PostId) AS UniquePostsVoted,
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY p.Score) AS Q1Score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.Score) AS Q3Score,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS ClosedPostRatio
    FROM Votes v
    INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    INNER JOIN Posts p ON p.Id = v.PostId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND v.VoteTypeId IN (2, 3, 5, 8, 9)
    GROUP BY DATE_TRUNC('month', v.CreationDate), vt.Name
),
CommentAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        MAX(c.Score) AS MaxCommentScore,
        SUM(CASE WHEN c.Score >= 5 THEN 1 ELSE 0 END) AS HighScoreComments,
        EXTRACT(EPOCH FROM (MAX(c.CreationDate) - MIN(c.CreationDate)))/86400 AS CommentSpanDays,
        COUNT(DISTINCT DATE_TRUNC('day', c.CreationDate)) AS ActiveCommentDays
    FROM Posts p
    INNER JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CommentCount >= 20
    GROUP BY p.Id, p.Title
)
SELECT 
    th.TagName AS PrimaryTag,
    th.Level AS TagLevel,
    th.QuestionCount,
    th.AvgScore AS TagAvgScore,
    ue.DisplayName AS TopExpert,
    ue.AnswerCount AS ExpertAnswers,
    ue.TotalScore AS ExpertTotalScore,
    ue.AcceptedAnswers,
    ue.MedianScore AS ExpertMedianScore,
    pe.Title AS EvolvedPostTitle,
    pe.EditCount,
    pe.UniqueEditors,
    pe.EditSpanHours,
    pe.HistoryTypes,
    vp.VoteMonth,
    vp.VoteType,
    vp.VoteCount,
    vp.UniqueVoters,
    vp.Q1Score,
    vp.Q3Score,
    ca.TotalComments,
    ca.AvgCommentLength,
    ca.UniqueCommenters,
    ca.HighScoreComments,
    ca.CommentSpanDays
FROM TagHierarchy th
LEFT JOIN UserExpertise ue ON ue.TagName = th.TagName AND ue.TagRank = 1
LEFT JOIN PostEvolution pe ON pe.Id = (
    SELECT p.Id 
    FROM Posts p 
    WHERE p.Tags LIKE '%<' || th.TagName || '>%' 
        AND p.PostTypeId = 1
    ORDER BY p.Score DESC, p.ViewCount DESC 
    LIMIT 1
)
LEFT JOIN VotingPatterns vp ON vp.VoteMonth = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
LEFT JOIN CommentAnalysis ca ON ca.PostId = pe.Id
WHERE th.Level <= 2
ORDER BY th.QuestionCount DESC, ue.TotalScore DESC, pe.EditCount DESC
LIMIT 100;
