WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        u.UpVotes,
        u.DownVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS EditCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN PostHistory ph ON ph.PostId = t.WikiPostId
    GROUP BY t.TagName, t.Count
),

RecentClosedQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        ph.CreationDate AS ClosedDate,
        CAST(ph.Comment AS INTEGER) AS CloseReasonId
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
),

UserRanking AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.QuestionCount,
        us.AnswerCount,
        us.BadgeCount,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC) AS Rank
    FROM UserStats us
)

SELECT 
    ur.Rank,
    ur.DisplayName,
    ur.Reputation,
    ur.NetVotes,
    ur.QuestionCount,
    ur.AnswerCount,
    ur.BadgeCount,
    COALESCE(rcq.Title, 'No recent closed question') AS RecentClosedTitle,
    COALESCE(rcq.ClosedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) AS RecentClosedDate,
    COALESCE(ct.TagName, 'N/A') AS TopTag,
    ct.TagRank
FROM UserRanking ur
LEFT JOIN LATERAL (
    SELECT rcq_inner.*
    FROM RecentClosedQuestions rcq_inner
    WHERE rcq_inner.Id = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = ur.Id
          AND p2.PostTypeId = 1
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
) rcq ON TRUE
LEFT JOIN LATERAL (
    SELECT t.TagName, t.TagRank
    FROM TagPopularity t
    ORDER BY t.TagRank
    LIMIT 1
) ct ON TRUE
WHERE ur.Rank <= 50
ORDER BY ur.Rank;