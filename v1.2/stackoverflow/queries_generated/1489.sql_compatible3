WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT Id, TagName, ExcerptPostId, WikiPostId, IsModeratorOnly, IsRequired, 1 AS Level
    FROM Tags
    WHERE Id IN (
        SELECT tg2.Id
        FROM Posts tg
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(substring(tg.Tags, 2, length(tg.Tags) - 2), '><')) AS Tag
        ) pt
        JOIN Tags tg2 ON pt.Tag = tg2.TagName
        WHERE tg.PostTypeId = 1
          AND tg.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '365 days'
    )
    UNION ALL
    SELECT tg.Id, tg.TagName, tg.ExcerptPostId, tg.WikiPostId, tg.IsModeratorOnly, tg.IsRequired, r.Level + 1
    FROM Tags tg
    INNER JOIN RecursiveTagHierarchy r ON tg.Id = (
        SELECT pl.RelatedPostId
        FROM PostLinks pl
        WHERE pl.PostId = r.ExcerptPostId
          AND pl.LinkTypeId = 1
        LIMIT 1
    )
    WHERE r.Level < 3
),
LatestEdits AS (
    SELECT ph.PostId, max(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
),
UserReputationRanks AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        row_number() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        coalesce(answer_data.AnswerCount,0) AS AnswerCount,
        coalesce(answer_data.AvgScore,0) AS AverageAnswerScore,
        coalesce(v.UpVotes,0) AS TotalUpVotes,
        total_fav.FavoriteCount,
        (SELECT count(*) FROM Comments c WHERE c.PostId = q.Id AND c.UserId IS NOT NULL) AS CommentsGiven,
        CASE
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts q
    LEFT JOIN (
        SELECT ParentId, count(*) AS AnswerCount, avg(Score) AS AvgScore
        FROM Posts
        WHERE ParentId IS NOT NULL AND PostTypeId = 2
        GROUP BY ParentId
    ) answer_data ON q.Id = answer_data.ParentId
    LEFT JOIN (
        SELECT PostId, sum(CASE WHEN VoteTypeId=2 THEN 1 ELSE 0 END) AS UpVotes
        FROM Votes
        GROUP BY PostId
    ) v ON q.Id = v.PostId
    LEFT JOIN (
        SELECT Id AS PostId, FavoriteCount
        FROM Posts
        WHERE PostTypeId = 1
    ) total_fav ON total_fav.PostId = q.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
),
CloseReasonsAggregated AS (
    SELECT cb.PostId, string_agg(distinct cr.Name, ', ') AS CloseReasons
    FROM PostHistory cb
    LEFT JOIN CloseReasonTypes cr ON CAST(cb.Comment AS integer) = cr.Id
    WHERE cb.PostHistoryTypeId = 10
    GROUP BY cb.PostId
)
SELECT 
    qs.QuestionId,
    qs.Title,
    coalesce(ur.DisplayName, 'Community') AS OwnerName,
    qs.QuestionCreationDate,
    qs.QuestionScore,
    qs.AnswerCount,
    qs.AverageAnswerScore,
    qs.TotalUpVotes,
    qs.FavoriteCount,
    qs.CommentsGiven,
    CASE
        WHEN (0.0 < 0) THEN 'Needs More Attention'
        WHEN qs.PostStatus = 'Closed' THEN 'Closed'
        ELSE 'Active'
    END AS QuestionSignal,
    cr.CloseReasons
FROM QuestionAnswerStats qs
LEFT JOIN Users u ON qs.OwnerUserId = u.Id
LEFT JOIN UserReputationRanks ur ON ur.UserId = qs.OwnerUserId
LEFT JOIN CloseReasonsAggregated cr ON cr.PostId = qs.QuestionId
ORDER BY qs.QuestionId;