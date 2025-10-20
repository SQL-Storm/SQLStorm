-- {"query": "2096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 664} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY SUM(p.Score) DESC) AS RowNum
    FROM 
        Users u
    INNER JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId IN (1, 2) AND
        p.CreationDate BETWEEN DATE_TRUNC('year', CURRENT_DATE) AND CURRENT_DATE
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING 
        COUNT(p.Id) > 10
), TopActiveUsersCTE AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        CreationDate
    FROM 
        ActiveUsers
    WHERE 
        RowNum = 1
), UserVotes AS (
    SELECT 
        u.Id AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id
), TagRankings AS (
    SELECT 
        t.TagName,
        COUNT(pl.PostId) AS LinkedPosts
    FROM 
        Tags t
    LEFT JOIN 
        PostLinks pl ON t.ExcerptPostId = pl.RelatedPostId
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(pl.PostId) > 0
), UsersWithTagsAndVotes AS (
    SELECT 
        a.UserId,
        a.DisplayName,
        a.Reputation,
        a.CreationDate,
        uv.UpVotes,
        uv.DownVotes,
        STRING_AGG(tr.TagName, ', ') AS TopTags
    FROM 
        TopActiveUsersCTE a
    LEFT JOIN 
        UserVotes uv ON a.UserId = uv.UserId
    LEFT JOIN 
        TagRankings tr ON a.UserId = tr.LinkedPosts
    GROUP BY 
        a.UserId, a.DisplayName, a.Reputation, a.CreationDate, uv.UpVotes, uv.DownVotes
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.CreationDate)) AS UserTenureYears,
    COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
    CASE 
        WHEN u.Reputation > 10000 THEN 'Veteran'
        WHEN u.Reputation > 5000 THEN 'Experienced'
        ELSE 'Rookie'
    END AS UserLevel,
    COALESCE(u.TopTags, 'No Tags') AS TopTags
FROM 
    UsersWithTagsAndVotes u
WHERE 
    u.Reputation IS NOT NULL
ORDER BY 
    UserLevel DESC, NetVotes DESC, UserTenureYears DESC;
