-- {"query": "39058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2814} 
WITH TopTags AS (
    SELECT
        t.TagName,
        COUNT(*) AS QCount
    FROM
        Posts p
        CROSS JOIN LATERAL unnest(
            string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')
        ) AS tag(TagName)
        JOIN Tags t ON t.TagName = tag.TagName
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    ORDER BY
        QCount DESC
    LIMIT 10
),
UserActivity AS (
    SELECT
        u.Id            AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p1.Id) AS QuestionsCount,
        COUNT(DISTINCT p2.Id) AS AnswersCount,
        COUNT(DISTINCT c.Id)  AS CommentsCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) AS UpDownVotesCast,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM
        Users u
        LEFT JOIN Posts p1 ON p1.OwnerUserId = u.Id AND p1.PostTypeId = 1
        LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id AND p2.PostTypeId = 2
        LEFT JOIN Comments c  ON c.UserId = u.Id
        LEFT JOIN Votes    v  ON v.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation
),
RecentEdits AS (
    SELECT
        ph.UserId,
        COUNT(*) AS RecentEditsCount
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6)
        AND ph.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY
        ph.UserId
),
AnswerStats AS (
    SELECT
        a.OwnerUserId AS UserId,
        AVG(a.Score)  AS AvgAnswerScore,
        MAX(a.Score)  AS MaxAnswerScore
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
    GROUP BY
        a.OwnerUserId
)
SELECT
    ua.DisplayName,
    ua.RepRank,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.UpDownVotesCast,
    COALESCE(re.RecentEditsCount,0) AS RecentEditsCount,
    COALESCE(ans.AvgAnswerScore,0)  AS AvgAnswerScore,
    COALESCE(ans.MaxAnswerScore,0)  AS MaxAnswerScore,
    tt.TagName,
    tt.QCount,
    b.Class                        AS BadgeClass,
    COUNT(b.Id) OVER (PARTITION BY ua.UserId, b.Class) AS BadgesOfClass,
    COALESCE(pl.OutboundLinks,0)   AS OutboundLinks,
    COALESCE(cl.InboundLinks,0)    AS InboundLinks
FROM
    UserActivity ua
    CROSS JOIN TopTags tt
    LEFT JOIN RecentEdits re ON re.UserId = ua.UserId
    LEFT JOIN AnswerStats ans ON ans.UserId = ua.UserId
    LEFT JOIN Badges b       ON b.UserId = ua.UserId
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS OutboundLinks
        FROM PostLinks pl
        JOIN Posts p ON p.Id = pl.PostId
        WHERE
            p.OwnerUserId = ua.UserId
            AND pl.LinkTypeId = 1
            AND EXISTS (
                SELECT 1
                FROM Posts pq
                WHERE pq.Id = p.Id
                  AND pq.Tags LIKE '%'||'<'
                                    ||tt.TagName
                                    ||'>'||'%'
            )
    ) pl ON TRUE
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS InboundLinks
        FROM PostLinks pl
        JOIN Posts rp ON rp.Id = pl.RelatedPostId
        WHERE
            rp.OwnerUserId = ua.UserId
            AND pl.LinkTypeId = 1
            AND EXISTS (
                SELECT 1
                FROM Posts rq
                WHERE rq.Id = rp.Id
                  AND rq.Tags LIKE '%'||'<'
                                    ||tt.TagName
                                    ||'>'||'%'
            )
    ) cl ON TRUE
WHERE
    ua.RepRank <= 50
ORDER BY
    ua.RepRank,
    tt.QCount DESC,
    ans.AvgAnswerScore DESC
LIMIT 100;