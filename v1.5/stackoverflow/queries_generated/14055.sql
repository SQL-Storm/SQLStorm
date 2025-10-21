-- {"query": "14055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 130760, "output_tokens": 55730} 
SELECT 
    ROUND(
        SUM(
            CASE 
                WHEN v.VoteTypeId = 2 THEN 1 
                WHEN v.VoteTypeId = 3 THEN -1
                ELSE 0
            END
        ) * 1.0 / 
        COUNT(p.Id)
    , 2) AS avg_vote_score,
    ROUND(
        AVG(
            CASE 
                WHEN p.PostTypeId = 1 THEN p.AnswerCount 
                ELSE 0
            END
        )
    , 2) AS avg_answer_count,
    ROUND(
        AVG(
            CASE
                WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
                ELSE 0 
            END
        )
    , 2) AS pct_questions_with_accepted_answer,
    ROUND(
        AVG(
            CASE
                WHEN p.PostTypeId = 1 THEN p.ViewCount
                ELSE 0
            END
        )
    , 2) AS avg_question_view_count,
    ROUND(
        AVG(
            CASE
                WHEN p.CommunityOwnedDate IS NOT NULL THEN DATEDIFF(p.LastEditDate, p.CommunityOwnedDate)
                ELSE DATEDIFF(p.LastEditDate, p.CreationDate)
            END    
        )
    , 2) AS avg_days_to_community_wiki,
    ROUND(
        AVG(
            CASE
                WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(p.ClosedDate, p.CreationDate)
                ELSE 0
            END
        )
    , 2) AS avg_days_to_close,
    ROUND(
        AVG(
            CASE
                WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1
                ELSE 0
            END
        )
    , 2) AS pct_questions_closed,
    ROUND(
        AVG(
            CASE
                WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL AND ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 1
                ELSE 0
            END    
        )
    , 2) AS pct_questions_closed_as_duplicate,
    STRING_AGG(
        CASE 
            WHEN t.TagName IS NOT NULL THEN t.TagName
            ELSE ''
        END, ', '
    ) AS top_tags
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN (
    SELECT 
        pt.PostId, 
        STRING_AGG(t.TagName, ', ') AS TagNames
    FROM 
        PostTags pt
    JOIN Tags t ON pt.TagId = t.Id
    GROUP BY pt.PostId
) t ON p.Id = t.PostId
GROUP BY 1;