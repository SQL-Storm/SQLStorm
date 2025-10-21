-- {"query": "27094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1380} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        STRING_AGG(DISTINCT t.TagName, ', ') AS MostUsedTags
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Posts pt ON p.Tags IS NOT NULL AND p.Tags LIKE '%<' || pt.Title || '>%'
    LEFT JOIN
        Tags t ON pt.Id = t.ExcerptPostId OR pt.Id = t.WikiPostId
    WHERE
        u.Reputation > 1000
        AND u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) AS PreviousScore,
        COALESCE(LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) AS NextScore,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryUserId,
        ph.Comment AS HistoryComment,
        CASE
            WHEN ph.PostHistoryTypeId = 10 THEN 'Post Closed'
            WHEN ph.PostHistoryTypeId = 11 THEN 'Post Reopened'
            WHEN ph.PostHistoryTypeId = 14 THEN 'Post Locked'
            WHEN ph.PostHistoryTypeId = 15 THEN 'Post Unlocked'
            ELSE 'Other'
        END AS HistoryTypeName,
        CASE
            WHEN ph.PostHistoryTypeId IN (10, 11, 14, 15) THEN 1
            ELSE 0
        END AS IsSignificantHistory,
        t.TagName AS RelatedTagName
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE
        p.Score > 50
        AND p.ViewCount > 1000
        AND p.CreationDate > NOW() - INTERVAL '1 year'
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalBadges,
    ua.MostUsedTags,
    pa.PostId,
    pa.PostTypeId,
    pa.PostCreationDate,
    pa.Score,
    pa.ViewCount,
    pa.OwnerUserId,
    pa.LastActivityDate,
    pa.Title,
    pa.AnswerCount,
    pa.FavoriteCount,
    pa.PreviousScore,
    pa.NextScore,
    pa.AcceptedAnswerId,
    pa.HistoryCreationDate,
    pa.HistoryUserId,
    pa.HistoryComment,
    pa.HistoryTypeName,
    pa.IsSignificantHistory,
    pa.RelatedTagName,
    CASE
        WHEN pa.PostTypeId = 1 THEN 'Question'
        WHEN pa.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeName
FROM
    UserActivity ua
JOIN
    PostActivity pa ON ua.UserId = pa.OwnerUserId
WHERE
    pa.Score > 100
    AND pa.ViewCount > 2000
    AND pa.LastActivityDate > NOW() - INTERVAL '6 months'
ORDER BY
    ua.Reputation DESC,
    pa.Score DESC,
    pa.ViewCount DESC;
