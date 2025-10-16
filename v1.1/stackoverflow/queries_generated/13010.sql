-- {"query": "13010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 915} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) AS QuestionRank,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate >= NOW() - INTERVAL '90 days'
    GROUP BY u.Id
),
TopContributors AS (
    SELECT UserId, QuestionsAsked, AnswersProvided, UpVotesReceived, DownVotesReceived, BadgesEarned, AvgPostScore
    FROM UserActivity
    WHERE QuestionRank <= 100
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ph.CreationDate AS LastEditDate,
        COALESCE(STRING_AGG(t.TagName, ', ' ORDER BY t.TagName), 'N/A') AS TagList
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            MAX(CreationDate) AS CreationDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) t ON true
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY p.Id, ph.CreationDate
),
AggregatedMetrics AS (
    SELECT 
        tc.UserId,
        COUNT(pm.PostId) AS TotalPosts,
        SUM(CASE WHEN pm.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        AVG(pm.Score) AS AvgScore,
        SUM(pm.ViewCount) AS TotalViews,
        SUM(pm.CommentCount) AS TotalComments,
        STRING_AGG(DISTINCT pm.TagList, '; ') AS AllTags
    FROM TopContributors tc
    LEFT JOIN PostMetrics pm ON tc.UserId = pm.OwnerUserId
    GROUP BY tc.UserId
)
SELECT 
    u.DisplayName,
    am.TotalPosts,
    am.TotalQuestions,
    am.AvgScore,
    am.TotalViews,
    am.TotalComments,
    am.AllTags,
    tc.UpVotesReceived - tc.DownVotesReceived AS NetVotes,
    RANK() OVER (ORDER BY am.TotalPosts DESC, tc.BadgesEarned DESC) AS ContributorRank
FROM AggregatedMetrics am
JOIN Users u ON am.UserId = u.Id
JOIN TopContributors tc ON am.UserId = tc.UserId
WHERE LENGTH(COALESCE(u.AboutMe, '')) > 100
ORDER BY ContributorRank;
