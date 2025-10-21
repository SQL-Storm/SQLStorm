WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.LastActivityDate) AS LastActive
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        TagName,
        COUNT(*) AS TagCount
    FROM (
        SELECT 
            REGEXP_REPLACE(t.TagName, '^.*$', '\\1') AS TagName
        FROM (
            SELECT
                TRIM(SPLIT_PART(unnest(string_to_array(Tags, '><')), '<', 1)) AS TagName
            FROM Posts
            WHERE PostTypeId = 1
        ) t
    ) t2
    GROUP BY 
        TagName
    ORDER BY 
        TagCount DESC
    LIMIT 10
),
PostVoteStats AS (
    SELECT 
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
),
RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        COALESCE(vs.UpVotes, 0) AS UpVotes,
        COALESCE(vs.DownVotes, 0) AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, (COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        PostVoteStats vs ON p.Id = vs.PostId
),
FinalStats AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.TotalPosts,
        us.TotalQuestions,
        us.TotalAnswers,
        tt.TagName,
        rp.Id AS PostId,
        rp.Title,
        rp.Rank,
        rp.Score
    FROM 
        UserStats us
    JOIN 
        TopTags tt ON us.TotalPosts > 0
    JOIN 
        RankedPosts rp ON us.TotalPosts = rp.Rank
)
SELECT 
    fs.DisplayName,
    fs.TagName,
    fs.Title,
    fs.Score,
    fs.Rank,
    fs.TotalQuestions,
    fs.TotalAnswers,
    CASE 
        WHEN fs.TotalQuestions > fs.TotalAnswers THEN 'More Questions' 
        ELSE 'More Answers' 
    END AS QuestionAnswerBalance,
    COALESCE(ROUND((CAST(fs.TotalAnswers AS DECIMAL) / NULLIF(CAST(fs.TotalQuestions AS DECIMAL), 0) * 100), 2), 0) AS AnswerToQuestionRatio
FROM 
    FinalStats fs
WHERE 
    fs.Rank <= 10 
ORDER BY 
    fs.Rank;