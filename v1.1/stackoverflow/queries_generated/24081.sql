-- {"query": "24081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3625} 

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
           string_agg(DISTINCT COALESCE(c.UserDisplayName,'anonymous'),
                      ', ') WITHIN GROUP (ORDER BY c.UserDisplayName) AS CommenterNames
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
           string_agg(DISTINCT COALESCE(c.UserDisplayName,'anonymous'),
                      ', ') WITHIN GROUP (ORDER BY c.UserDisplayName) AS CommenterNames
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
           unnest(string_to_array(substring(ap.Tags FROM 2 FOR char_length(ap.Tags)-2),
                               '><')) AS Tag
    FROM all_posts ap
),
ranked AS (
    SELECT tg.*,
           DENSE_RANK() OVER (PARTITION BY Tag
                               ORDER BY UpVotes DESC, Score DESC) AS TagRank,
           CASE
               WHEN CommentCnt = 0 THEN 'No comments'
               WHEN UpVotes > 100 THEN 'Very upvoted'
               ELSE 'Normal' END AS CommentCategory
    FROM tagged tg
)
SELECT *,
       CONCAT('[', Tag, ']', ': ', Title)            AS TaggedTitle,
       CASE
           WHEN UpVotes IS NULL OR UpVotes = 0 THEN 'Zero upvotes'
           ELSE 'Positive' END                       AS UpvoteStatus
FROM ranked
ORDER BY Tag, TagRank, UpVotes DESC
LIMIT 2000;
