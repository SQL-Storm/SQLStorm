WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.Score, 0) ELSE 0 END) AS QuestionScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(p.Score, 0) ELSE 0 END) AS AnswerScoreSum,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteGivenCount,
        COUNT(DISTINCT vr.Id) AS VoteReceivedCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    -- replace incorrect correlated reference for vote received: join Posts to get post owner for votes on those posts
    LEFT JOIN Votes vr ON vr.PostId IS NOT NULL
    LEFT JOIN Posts post_vr ON post_vr.Id = vr.PostId AND post_vr.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
),
EngagementScore AS (
    SELECT 
        Id,
        Reputation,
        PostCount,
        QuestionScoreSum,
        AnswerScoreSum,
        CommentCount,
        VoteGivenCount,
        VoteReceivedCount,
        BadgeCount,
        (Reputation * 0.1 + PostCount * 1 + QuestionScoreSum * 2 + AnswerScoreSum * 3 + CommentCount * 0.5 + VoteGivenCount * 0.1 + VoteReceivedCount * 1 + BadgeCount * 5) AS Score
    FROM UserStats
),
RankedUsers AS (
    SELECT 
        Id,
        Reputation,
        PostCount,
        QuestionScoreSum,
        AnswerScoreSum,
        CommentCount,
        VoteGivenCount,
        VoteReceivedCount,
        BadgeCount,
        Score,
        ROW_NUMBER() OVER (ORDER BY Score DESC) AS Rank
    FROM EngagementScore
),
PostTags AS (
    SELECT
        p.Id AS PostId,
        -- remove surrounding <> from tags like '<1><2>' and split on '><'
        TRIM(BOTH '<>' FROM p.Tags) AS trimmed_tags
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
SplitTags AS (
    SELECT
        pt.PostId,
        CAST(tid AS INTEGER) AS TagId
    FROM PostTags pt,
    -- use standard string_split approach: replace '><' with ',' then split by ',' using a generic unnest of string_to_array
    LATERAL (
        SELECT value AS tid
        FROM UNNEST(string_to_array(replace(pt.trimmed_tags, '><', ','), ',')) AS t(value)
    ) s
),
TagCounts AS (
    SELECT
        st.TagId,
        COUNT(*) AS cnt
    FROM SplitTags st
    GROUP BY st.TagId
)
SELECT 
    ru.Id,
    ru.Reputation,
    ru.PostCount,
    ru.QuestionScoreSum,
    ru.AnswerScoreSum,
    ru.CommentCount,
    ru.VoteGivenCount,
    ru.VoteReceivedCount,
    ru.BadgeCount,
    ru.Score,
    ru.Rank,
    STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags
FROM RankedUsers ru
LEFT JOIN Posts p ON ru.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT tt.TagName
    FROM Tags tt
    JOIN (
        SELECT st.TagId
        FROM SplitTags st
        WHERE st.PostId = p.Id
    ) st2 ON tt.Id = st2.TagId
    LEFT JOIN TagCounts tc ON tt.Id = tc.TagId
    ORDER BY COALESCE(tc.cnt, 0) DESC
    LIMIT 5
) t ON TRUE
WHERE ru.Rank <= 10
GROUP BY ru.Id, ru.Reputation, ru.PostCount, ru.QuestionScoreSum, ru.AnswerScoreSum, ru.CommentCount, ru.VoteGivenCount, ru.VoteReceivedCount, ru.BadgeCount, ru.Score, ru.Rank
ORDER BY ru.Rank;