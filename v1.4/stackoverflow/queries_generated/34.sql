-- {"query": "34.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 835} 
WITH
    q AS (
        SELECT
            p.Id AS PostId,
            p.Title,
            p.PostTypeId,
            p.CreationDate,
            p.LastActivityDate,
            p.Score,
            p.ViewCount,
            p.OwnerUserId,
            p.Tags,
            p.Body,
            p.AcceptedAnswerId,
            p.CommentCount,
            p.FavoriteCount,
            p.ClosedDate,
            p.CommunityOwnedDate,
            p.ContentLicense
        FROM Posts p
        -- focus on questions with high activity
        WHERE p.PostTypeId = 1
          AND p.ViewCount > 100
          AND p.Score > 0
    ),
    recent_comments AS (
        SELECT
            c.PostId,
            COUNT(*) AS CommentCountRecent
        FROM Comments c
        WHERE c.CreationDate >= NOW() - INTERVAL '30 days'
        GROUP BY c.PostId
    ),
    recent_votes AS (
        SELECT
            V.PostId,
            SUM(CASE WHEN VT.Id IN (2,3) THEN 1 ELSE 0 END) AS NetVotes30
        FROM Votes V
        JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
        WHERE V.CreationDate >= NOW() - INTERVAL '30 days'
        GROUP BY V.PostId
    ),
    top_tags AS (
        SELECT
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
            COUNT(*) AS TagCount
        FROM Posts p
        CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
        WHERE p.PostTypeId = 1
        GROUP BY TagName
    ),
    badge_influence AS (
        SELECT
            u.Id AS UserId,
            COUNT(b.Id) AS BadgesEarned
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),
    last_editor AS (
        SELECT
            p.OwnerUserId,
            p.LastEditorUserId,
            p.LastEditDate
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    filtered AS (
        SELECT
            q.*,
            rc.CommentCountRecent,
            rv.NetVotes30,
            tt.TagName,
            tt.TagCount,
            bi.BadgesEarned
        FROM q
        LEFT JOIN recent_comments rc ON rc.PostId = q.Id
        LEFT JOIN recent_votes rv ON rv.PostId = q.Id
        LEFT JOIN top_tags tt ON tt.TagCount = (
            SELECT MAX(TagCount) FROM top_tags
        )
        LEFT JOIN badge_influence bi ON bi.UserId = q.OwnerUserId
        LEFT JOIN last_editor le ON le.OwnerUserId = q.OwnerUserId
    ),
    judging AS (
        SELECT
            f.*,
            CASE
                WHEN f.CommentCount IS NULL THEN 0
                ELSE f.CommentCount
            END AS CommentCountFinal,
            CASE
                WHEN f.NetVotes30 IS NULL THEN 0
                ELSE f.NetVotes30
            END AS NetVotes30Final
        FROM filtered f
    )
SELECT
    j.PostId,
    j.Title,
    j.PostTypeId,
    j.CreationDate,
    j.LastActivityDate,
    j.Score,
    j.ViewCount,
    j.OwnerUserId,
    j.Tags,
    j.Body,
    j.AcceptedAnswerId,
    j.CommentCountFinal,
    j.FavoriteCount,
    j.ClosedDate,
    j.CommunityOwnedDate,
    j.ContentLicense,
    j.TagName,
    j.TagCount,
    j.BadgesEarned,
    j.LastEditorUserId,
    j.LastEditDate
FROM judging j
ORDER BY
    j.LastActivityDate DESC,
    j.Score DESC,
    j.ViewCount DESC
LIMIT 100;