-- {"query": "35013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 751} 
WITH TopContributors AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(p.Score) AS TotalScore,
        RANK() OVER (ORDER BY SUM(p.Score) DESC, COUNT(DISTINCT p.Id) DESC) AS UserRank
    FROM 
        Users u
        JOIN Posts p ON p.OwnerUserId = u.Id
        JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE 
        p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year'
        AND pt.Name IN ('Question', 'Answer')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 20
),
TopBadgeHolders AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) FILTER (WHERE b.Class = 1) DESC) AS GoldRank
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year'
    GROUP BY b.UserId
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT c.Id) AS CommentCount,
        p.ViewCount
    FROM
        Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE
        p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year'
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.ViewCount
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.TotalPosts,
    tc.QuestionsAsked,
    tc.AnswersGiven,
    tc.TotalScore,
    tb.GoldBadges,
    tb.SilverBadges,
    tb.BronzeBadges,
    AVG(pe.UpVotes) AS AvgUpVotesPerPost,
    AVG(pe.DownVotes) AS AvgDownVotesPerPost,
    AVG(pe.CommentCount) AS AvgCommentsPerPost,
    AVG(pe.ViewCount) AS AvgViewsPerPost,
    MAX(pe.UpVotes) AS MaxOnePostUpvotes,
    MAX(pe.ViewCount) AS MaxOnePostViews,
    tc.UserRank,
    tb.GoldRank
FROM 
    TopContributors tc
    LEFT JOIN TopBadgeHolders tb ON tb.UserId = tc.UserId
    LEFT JOIN PostEngagement pe ON pe.OwnerUserId = tc.UserId
WHERE
    tc.UserRank <= 50
GROUP BY 
    tc.UserId, tc.DisplayName, tc.TotalPosts, tc.QuestionsAsked, tc.AnswersGiven,
    tc.TotalScore, tc.UserRank, tb.GoldBadges, tb.SilverBadges, tb.BronzeBadges, tb.GoldRank
ORDER BY
    tc.UserRank
;