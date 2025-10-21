WITH user_stats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS question_count,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)               AS answer_count,
           COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 1),0)  AS question_score,
           COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 2),0)  AS answer_score,
           COUNT(b.Id)                                               AS badge_total,
           COUNT(b.Id) FILTER (WHERE b.Class = 1)                    AS gold_badges,
           COUNT(b.Id) FILTER (WHERE b.Class = 2)                    AS silver_badges,
           COUNT(b.Id) FILTER (WHERE b.Class = 3)                    AS bronze_badges,
           MAX(p.CreationDate)                                      AS last_post_date
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_tags AS (
    SELECT t.TagName,
           t.Count,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
post_activity AS (
    SELECT p.Id,
           p.PostTypeId,
           p.Title,
           p.CreationDate,
           p.LastActivityDate,
           COALESCE(vu.cnt,0) AS upvotes,
           COALESCE(vd.cnt,0) AS downvotes,
           COALESCE(cc.cnt,0) AS comment_count,
           ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lt.Name IS NOT NULL) AS link_type_names
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS cnt
        FROM Votes
        WHERE VoteTypeId = 2               -- UpMod
        GROUP BY PostId
    ) vu ON vu.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS cnt
        FROM Votes
        WHERE VoteTypeId = 3               -- DownMod
        GROUP BY PostId
    ) vd ON vd.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS cnt
        FROM Comments
        GROUP BY PostId
    ) cc ON cc.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY p.Id, p.PostTypeId, p.Title, p.CreationDate, p.LastActivityDate,
             vu.cnt, vd.cnt, cc.cnt
),
recent_edits AS (
    SELECT ph.PostId,
           MAX(ph.CreationDate)                                   AS last_edit_date,
           COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS edit_count,
           COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS distinct_editors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11)                     -- edits and close/reopen
    GROUP BY ph.PostId
)
SELECT us.Id               AS UserId,
       us.DisplayName,
       us.Reputation,
       us.question_count,
       us.answer_count,
       us.question_score,
       us.answer_score,
       us.gold_badges,
       us.silver_badges,
       us.bronze_badges,
       pa.Id                AS PostId,
       pa.Title,
       pa.PostTypeId,
       pa.CreationDate,
       pa.LastActivityDate,
       pa.upvotes,
       pa.downvotes,
       pa.comment_count,
       pa.link_type_names,
       re.last_edit_date,
       re.edit_count,
       re.distinct_editors,
       tt.TagName,
       tt.Count             AS TagUseCount,
       tt.tag_rank
FROM user_stats us
LEFT JOIN LATERAL (
    SELECT *
    FROM post_activity pa
    WHERE pa.Id = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = us.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
) pa ON TRUE
LEFT JOIN recent_edits re ON re.PostId = pa.Id
LEFT JOIN LATERAL (
    SELECT t.TagName, t.Count, t.tag_rank
    FROM top_tags t
    WHERE t.TagName = ANY (
        string_to_array(
            regexp_replace(pa.Title, '[<>]', '', 'g'),
            '><'
        )
    )
    ORDER BY t.tag_rank
    LIMIT 1
) tt ON TRUE
WHERE us.Reputation > 10000
ORDER BY us.Reputation DESC,
         (us.question_score + us.answer_score) DESC
LIMIT 100;