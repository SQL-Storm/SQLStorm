WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS QuestionCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViews,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM 
        Users u
    INNER JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000
        AND p.CreationDate >= DATE '2010-01-01'
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
PostTagPairs AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        TRIM(tag) AS TagName
    FROM
        Posts p
        -- Use a generic splitting approach compatible with many dialects.
        -- For dialects without regexp_split_to_table or LATERAL, this section may need adjustment.
        JOIN LATERAL (
            SELECT value AS tag
            FROM (
                SELECT regexp_split_to_table(
                    CASE 
                        WHEN p.Tags LIKE '<%' AND p.Tags LIKE '%>' THEN substring(p.Tags FROM 2 FOR length(p.Tags)-2)
                        ELSE p.Tags
                    END
                , '><') AS value
            ) s
        ) tt ON TRUE
    WHERE
        p.PostTypeId = 1
),
TaggedPosts AS (
    SELECT 
        pt.PostId,
        pt.Title,
        pt.Score,
        pt.ViewCount,
        pt.OwnerUserId,
        STRING_AGG(t.TagName, ', ') AS TagsList
    FROM 
        PostTagPairs pt
    INNER JOIN 
        Tags t ON t.TagName = pt.TagName
    INNER JOIN 
        TopTags tt ON t.Id = tt.TagId
    WHERE 
        tt.TagRank <= 10
    GROUP BY 
        pt.PostId, pt.Title, pt.Score, pt.ViewCount, pt.OwnerUserId
),
VoteAndCommentStats AS (
    SELECT 
        p.PostId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        TaggedPosts p
    LEFT JOIN 
        Votes v ON p.PostId = v.PostId
    LEFT JOIN 
        Comments c ON p.PostId = c.PostId
    GROUP BY 
        p.PostId
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    INNER JOIN 
        TaggedPosts tp ON ph.PostId = tp.PostId
    WHERE 
        ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY 
        ph.PostId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgViews,
    ua.QuestionCount,
    ua.AnswerCount,
    tp.PostId,
    tp.Title,
    tp.Score AS PostScore,
    tp.ViewCount AS PostViews,
    tp.TagsList,
    vcs.VoteCount,
    vcs.Upvotes,
    vcs.Downvotes,
    vcs.CommentCount,
    vcs.AvgCommentScore,
    eh.EditCount,
    eh.LastEditDate,
    RANK() OVER (PARTITION BY ua.UserId ORDER BY tp.Score DESC) AS PostRank
FROM 
    UserActivity ua
INNER JOIN 
    TaggedPosts tp ON ua.UserId = tp.OwnerUserId
LEFT JOIN 
    VoteAndCommentStats vcs ON tp.PostId = vcs.PostId
LEFT JOIN 
    EditHistory eh ON tp.PostId = eh.PostId
WHERE 
    ua.TotalScore > 1000
ORDER BY 
    ua.Reputation DESC, tp.Score DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;