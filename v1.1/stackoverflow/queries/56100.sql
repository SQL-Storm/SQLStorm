WITH top_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS num_posts, 
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS num_upvoted_posts
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
top_tags AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS num_posts
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM (
                SELECT regexp_split_to_table(p.Tags, '><') AS tag_id
            ) AS tag_table
            WHERE tag_table.tag_id = CAST(t.Id AS text)
        )
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
tag_scores AS (
    SELECT 
        t.TagName, 
        SUM(p.Score) AS total_score
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM (
                SELECT regexp_split_to_table(p.Tags, '><') AS tag_id
            ) AS tag_table
            WHERE tag_table.tag_id = CAST(t.Id AS text)
        )
    GROUP BY 
        t.TagName
)
SELECT 
    tu.DisplayName, 
    tu.num_posts, 
    tu.num_upvoted_posts, 
    tt.num_posts AS num_tag_posts, 
    ts.total_score AS total_tag_score,
    tu.Id,
    tt.TagName,
    ts.TagName
FROM 
    top_users tu
JOIN 
    top_tags tt ON EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = tu.Id
          AND p.Tags IS NOT NULL
          AND tt.TagName = ANY(regexp_split_to_array(p.Tags, '><'))
    )
JOIN 
    tag_scores ts ON tt.TagName = ts.TagName
GROUP BY
    tu.DisplayName,
    tu.num_posts,
    tu.num_upvoted_posts,
    tt.num_posts,
    ts.total_score,
    tu.Id,
    tt.TagName,
    ts.TagName
ORDER BY 
    tu.num_posts DESC, 
    tu.num_upvoted_posts DESC, 
    tt.num_posts DESC, 
    ts.total_score DESC;