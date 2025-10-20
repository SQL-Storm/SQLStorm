WITH
    question_posts AS (
        SELECT
            p.Id          AS QId,
            p.Tags,
            p.CreationDate,
            p.LastActivityDate,
            p.ClosedDate,
            p.Score       AS QScore,
            p.OwnerUserId
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),

    answers AS (
        SELECT
            a.ParentId    AS QId,
            a.Id          AS AId,
            a.CreationDate,
            a.Score       AS AScore,
            a.OwnerUserId
        FROM Posts a
        WHERE a.PostTypeId = 2
    ),

    tag_q_counts AS (
        SELECT
            t.TagName,
            COUNT(DISTINCT q.QId) AS TotalQuestions
        FROM Tags t
        JOIN question_posts q
          ON q.Tags IS NOT NULL
         AND q.Tags LIKE ('%' || t.TagName || '%')
        GROUP BY t.TagName
    ),

    dup_counts AS (
        SELECT
            t.TagName,
            COUNT(DISTINCT pl.RelatedPostId) AS DuplicatePosts
        FROM Tags t
        JOIN question_posts q
          ON q.Tags LIKE ('%' || t.TagName || '%')
        JOIN PostLinks pl
              ON pl.PostId = q.QId
             AND pl.LinkTypeId = 3
        GROUP BY t.TagName
    ),

    tag_stats AS (
        SELECT
            tq.TagName,
            tq.TotalQuestions,
            COALESCE(dc.DuplicatePosts, 0) AS DuplicatePosts,
            COUNT(DISTINCT q.QId) FILTER (WHERE q.ClosedDate IS NOT NULL) AS ClosedQuestions,
            AVG(EXTRACT(EPOCH FROM (q.LastActivityDate - q.CreationDate))) AS AvgActivitySeconds,
            MAX(a.AScore) AS MaxAnswerScore,
            MIN(a.AScore) AS MinAnswerScore,
            MAX(a.AScore) - MIN(a.AScore) AS ScoreDiff
        FROM tag_q_counts tq
        LEFT JOIN dup_counts dc         ON dc.TagName = tq.TagName
        JOIN question_posts q           ON q.Tags LIKE ('%' || tq.TagName || '%')
        LEFT JOIN answers a             ON a.QId = q.QId
        GROUP BY tq.TagName, dc.DuplicatePosts, tq.TotalQuestions
    ),

    ranked_answerers AS (
        SELECT
            tg.TagName,
            u.DisplayName,
            SUM(a.AScore) AS TotalAnswerScore,
            ROW_NUMBER() OVER (PARTITION BY tg.TagName ORDER BY SUM(a.AScore) DESC) AS rn
        FROM Tags tg
        JOIN question_posts qp
            ON qp.Tags LIKE ('%' || tg.TagName || '%')
        JOIN answers a
            ON a.QId = qp.QId
        JOIN Users u
            ON u.Id = a.OwnerUserId
        GROUP BY tg.TagName, u.DisplayName
    ),

    top_answerer AS (
        SELECT
            TagName,
            DisplayName,
            TotalAnswerScore
        FROM ranked_answerers
        WHERE rn = 1
    )

SELECT
    st.TagName,
    st.TotalQuestions,
    st.DuplicatePosts,
    st.ClosedQuestions,
    st.AvgActivitySeconds,
    st.MaxAnswerScore,
    st.MinAnswerScore,
    st.ScoreDiff,
    ta.DisplayName         AS TopAnswerer,
    ta.TotalAnswerScore    AS TopAnswererScore
FROM tag_stats st
JOIN top_answerer ta
      ON ta.TagName = st.TagName
ORDER BY st.ScoreDiff DESC, st.TotalQuestions DESC
LIMIT 20;