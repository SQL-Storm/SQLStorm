WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(v.Id) AS TotalVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
PopularTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TotalUsage,
        COUNT(p.Id) AS QuestionsWithTag,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.Score) AS MaxQuestionScore,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        t.Count > 1000
    GROUP BY
        t.Id, t.TagName, t.Count
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.LastPostDate,
    ua.LastCommentDate,
    ua.TotalVotes,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    pt.TagId,
    pt.TagName,
    pt.TotalUsage,
    pt.QuestionsWithTag,
    pt.AvgQuestionScore,
    pt.MaxQuestionScore,
    pt.UniqueVoters,
    (SELECT COUNT(*)
     FROM PostHistory ph
     WHERE ph.UserId = ua.UserId
       AND ph.PostHistoryTypeId IN (10, 11, 12, 19, 20)) AS CloseVotes,
    (SELECT COUNT(pl.Id)
     FROM PostLinks pl
     WHERE pl.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId)
       AND pl.LinkTypeId = 3) AS DuplicateLinks,
    ROW_NUMBER() OVER (PARTITION BY pt.TagId ORDER BY ua.Reputation DESC) AS RankInTag
FROM
    UserActivity ua
JOIN
    PopularTags pt ON POSITION('<' || pt.TagName || '>' IN (SELECT STRING_AGG(Tags, ' ') FROM Posts WHERE OwnerUserId = ua.UserId)) > 0
WHERE
    ua.TotalPosts > 10
    AND pt.QuestionsWithTag > 5
ORDER BY
    pt.TotalUsage DESC,
    ua.Reputation DESC;