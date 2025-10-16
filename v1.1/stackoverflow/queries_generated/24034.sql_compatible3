WITH recent_posts AS (
    SELECT p.Id AS PostId,
           p.Tags,
           p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2023-01-01'
),
post_votes AS (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1
                    WHEN VoteTypeId = 3 THEN -1
                    ELSE 0 END) AS VoteScore
    FROM Votes
    GROUP BY PostId
),
post_comments AS (
    SELECT PostId,
           COUNT(*) AS CommentCnt,
           AVG(CASE WHEN Score > 0 THEN Score END) AS AvgCommentScore
    FROM Comments
    GROUP BY PostId
),
post_tags AS (
    SELECT rp.PostId,
           -- split Tags by angle-bracketed tokens; replace function per dialect if needed
           -- here simulate split by using a generic approach: assume Tags format '<tag1><tag2>' -> extract tags via a numbers/tally approach
           SUBSTRING(rp.Tags FROM start_pos FOR (end_pos - start_pos)) AS TagName
    FROM recent_posts rp
    JOIN (
      -- generate positions of '<' and '>' pairs; this subquery is a generic placeholder and may need adjustment per SQL dialect
      SELECT rp2.PostId,
             (pos.open_pos + 1) AS start_pos,
             pos.close_pos AS end_pos
      FROM recent_posts rp2
      CROSS JOIN LATERAL (
        SELECT open_pos, close_pos
        FROM (
          SELECT 
            (n1) AS open_pos,
            (n2) AS close_pos
          FROM (
            -- generate sequence positions up to reasonable max tag length; replace with appropriate sequence generator per dialect
            VALUES (1,6),(7,13),(14,20),(21,27),(28,34)
          ) AS seq(n1,n2)
        ) AS p
      ) AS pos
      WHERE rp2.Tags IS NOT NULL
    ) AS positions ON positions.PostId = rp.PostId
    WHERE rp.Tags IS NOT NULL
),
tag_stats AS (
    SELECT pt.TagName,
           COUNT(DISTINCT pt.PostId) AS QuestionCount,
           AVG(COALESCE(pv.VoteScore, 0)) AS AvgPostScore,
           AVG(COALESCE(pc.AvgCommentScore, 0)) AS AvgCommentScore
    FROM post_tags pt
    LEFT JOIN post_votes pv ON pt.PostId = pv.PostId
    LEFT JOIN post_comments pc ON pt.PostId = pc.PostId
    GROUP BY pt.TagName
    HAVING AVG(COALESCE(pc.AvgCommentScore, 0)) > 5
),
duplicate_links AS (
    SELECT pt.TagName,
           COUNT(*) AS DupLinkCnt
    FROM post_tags pt
    JOIN PostLinks pl ON pl.PostId = pt.PostId AND pl.LinkTypeId = 3
    GROUP BY pt.TagName
),
final AS (
    SELECT ts.TagName,
           ts.QuestionCount,
           ts.AvgPostScore,
           ts.AvgCommentScore,
           ROW_NUMBER() OVER (ORDER BY ts.QuestionCount DESC) AS TagRank,
           COALESCE(dl.DupLinkCnt, 0) AS DuplicateLinks,
           (
             SELECT COUNT(*)
             FROM Badges b
             JOIN Users u ON b.UserId = u.Id
             WHERE b.Class = 1
               AND EXISTS (
                   SELECT 1 FROM Posts p2
                   WHERE p2.OwnerUserId = u.Id
                     AND p2.Tags LIKE '%' || ts.TagName || '%'
               )
           ) AS GoldBadgeOwners,
           (
             SELECT AVG(vs_sum.VoteScore)
             FROM (
               SELECT p3.Id AS PostId,
                      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS VoteScore
               FROM Posts p3
               LEFT JOIN Votes v ON p3.Id = v.PostId
               WHERE p3.Tags LIKE '%' || ts.TagName || '%'
               GROUP BY p3.Id
             ) vs_sum
           ) AS AvgVoteScoreInTag
    FROM tag_stats ts
    LEFT JOIN duplicate_links dl ON dl.TagName = ts.TagName
    GROUP BY ts.TagName, ts.QuestionCount, ts.AvgPostScore, ts.AvgCommentScore, dl.DupLinkCnt
)
SELECT TagName,
       QuestionCount,
       AvgPostScore,
       AvgCommentScore,
       TagRank,
       DuplicateLinks,
       GoldBadgeOwners,
       AvgVoteScoreInTag
FROM final
UNION ALL
SELECT
    'DummyTag' AS TagName,
    0 AS QuestionCount,
    0.0 AS AvgPostScore,
    0.0 AS AvgCommentScore,
    CAST(NULL AS INTEGER) AS TagRank,
    0 AS DuplicateLinks,
    0 AS GoldBadgeOwners,
    CAST(NULL AS NUMERIC) AS AvgVoteScoreInTag
ORDER BY TagRank;