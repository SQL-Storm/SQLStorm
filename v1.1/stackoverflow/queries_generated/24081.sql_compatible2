WITH recent_posts AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           p.Tags,
           p.OwnerUserId,
           u.DisplayName AS OwnerName,
           u.Reputation AS OwnerReputation,
           (SELECT COUNT(*) FROM Votes v
                WHERE v.PostId = p.Id AND v.VoteTypeId = 2)            AS UpVotes,
           (SELECT COUNT(*) FROM Votes v
                WHERE v.PostId = p.Id AND v.VoteTypeId = 3)            AS DownVotes,
           (SELECT COUNT(*) FROM Comments c
                WHERE c.PostId = p.Id)                                 AS CommentCnt,
           COALESCE((SELECT MAX(c.CreationDate) FROM Comments c
                   WHERE c.PostId = p.Id), p.CreationDate)             AS LatestComment,
           STRING_AGG(COALESCE(c.UserDisplayName,'anonymous'), ', ' ORDER BY c.UserDisplayName) AS CommenterNames
    FROM Posts        p
    LEFT JOIN Users   u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id,
             p.Title,
             p.Score,
             p.ViewCount,
             p.CreationDate,
             p.Tags,
             p.OwnerUserId,
             u.DisplayName,
             u.Reputation
),
closed_posts AS (
    SELECT p.Id,
           p.Title,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           p.Tags,
           p.OwnerUserId,
           u.DisplayName AS OwnerName,
           u.Reputation AS OwnerReputation,
           (SELECT COUNT(*) FROM Votes v
                WHERE v.PostId = p.Id AND v.VoteTypeId = 2)            AS UpVotes,
           (SELECT COUNT(*) FROM Votes v
                WHERE v.PostId = p.Id AND v.VoteTypeId = 3)            AS DownVotes,
           (SELECT COUNT(*) FROM Comments c
                WHERE c.PostId = p.Id)                                 AS CommentCnt,
           COALESCE((SELECT MAX(c.CreationDate) FROM Comments c
                   WHERE c.PostId = p.Id), p.CreationDate)             AS LatestComment,
           STRING_AGG(COALESCE(c.UserDisplayName,'anonymous'), ', ' ORDER BY c.UserDisplayName) AS CommenterNames
    FROM Posts        p
    LEFT JOIN Users   u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
    GROUP BY p.Id,
             p.Title,
             p.Score,
             p.ViewCount,
             p.CreationDate,
             p.Tags,
             p.OwnerUserId,
             u.DisplayName,
             u.Reputation
),
all_posts AS (
    SELECT * FROM recent_posts
    UNION ALL
    SELECT * FROM closed_posts
),
tagged AS (
    SELECT ap.*,
           TRIM(tag) AS Tag
    FROM all_posts ap,
         LATERAL (
             SELECT value AS tag
             FROM ( -- split tags like '<tag1><tag2>' into rows
                   SELECT regexp_split_to_table(
                            SUBSTRING(ap.Tags FROM 2 FOR (LENGTH(ap.Tags) - 2)),
                            '><'
                         ) AS value
                  ) s
         ) split
),
ranked AS (
    SELECT tg.Id,
           tg.Title,
           tg.Score,
           tg.ViewCount,
           tg.CreationDate,
           tg.Tags,
           tg.OwnerUserId,
           tg.OwnerName,
           tg.OwnerReputation,
           tg.UpVotes,
           tg.DownVotes,
           tg.CommentCnt,
           tg.LatestComment,
           tg.CommenterNames,
           tg.Tag,
           DENSE_RANK() OVER (PARTITION BY tg.Tag
                               ORDER BY tg.UpVotes DESC, tg.Score DESC) AS TagRank,
           CASE
               WHEN tg.CommentCnt = 0 THEN 'No comments'
               WHEN tg.UpVotes > 100 THEN 'Very upvoted'
               ELSE 'Normal' END AS CommentCategory
    FROM tagged tg
)
SELECT Id,
       Title,
       Score,
       ViewCount,
       CreationDate,
       Tags,
       OwnerUserId,
       OwnerName,
       OwnerReputation,
       UpVotes,
       DownVotes,
       CommentCnt,
       LatestComment,
       CommenterNames,
       Tag,
       TagRank,
       CommentCategory,
       '[' || Tag || ']' || ': ' || Title            AS TaggedTitle,
       CASE
           WHEN UpVotes IS NULL OR UpVotes = 0 THEN 'Zero upvotes'
           ELSE 'Positive' END                       AS UpvoteStatus
FROM ranked
ORDER BY Tag, TagRank, UpVotes DESC
LIMIT 2000;