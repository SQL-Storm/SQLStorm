-- {"query": "11037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 833} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS AuthorDisplayName, 
        u.Reputation AS AuthorReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS HighestBountyAmount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
AuthorReputationRank AS (
    SELECT 
        Id, 
        AuthorDisplayName, 
        AuthorReputation, 
        RANK() OVER (ORDER BY AuthorReputation DESC) AS ReputationRank
    FROM 
        RecentPosts
),
TopAuthors AS (
    SELECT 
        Id, 
        Title, 
        CreationDate, 
        Score, 
        ViewCount, 
        AuthorDisplayName, 
        AuthorReputation, 
        VoteCount, 
        UpVoteCount, 
        DownVoteCount, 
        HighestBountyAmount, 
        CommentCount, 
        ReputationRank
    FROM 
        RecentPosts
    WHERE 
        ReputationRank <= 10
),
PostTags AS (
    SELECT 
        PostId, 
        TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
),
TagFrequency AS (
    SELECT 
        TagName, 
        COUNT(*) AS Frequency
    FROM 
        PostTags
    GROUP BY 
        TagName
),
TopTags AS (
    SELECT 
        TagName
    FROM 
        TagFrequency
    ORDER BY 
        Frequency DESC
    LIMIT 10
)
SELECT 
    tp.Id, 
    tp.Title, 
    tp.CreationDate, 
    tp.Score, 
    tp.ViewCount, 
    tp.AuthorDisplayName, 
    tp.AuthorReputation, 
    tp.VoteCount, 
    tp.UpVoteCount, 
    tp.DownVoteCount, 
    tp.HighestBountyAmount, 
    tp.CommentCount, 
    tp.ReputationRank, 
    COALESCE(STRING_AGG(tf.TagName, ', '), 'No Tags') AS PopularTags
FROM 
    TopAuthors tp
LEFT JOIN 
    PostTags pt ON tp.Id = pt.PostId
LEFT JOIN 
    TopTags tf ON pt.TagName = tf.TagName
GROUP BY 
    tp.Id, tp.Title, tp.CreationDate, tp.Score, tp.ViewCount, tp.AuthorDisplayName, tp.AuthorReputation, tp.VoteCount, tp.UpVoteCount, tp.DownVoteCount, tp.HighestBountyAmount, tp.CommentCount, tp.ReputationRank
ORDER BY 
    tp.Score DESC, 
    tp.ViewCount DESC, 
    tp.ReputationRank ASC;
