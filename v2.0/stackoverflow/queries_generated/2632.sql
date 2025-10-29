-- {"query": "2632.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1971} 
with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName,
        b.Name as BadgeName, b.Class, b.Date,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
LatestUserBadges as (
    select UserId, DisplayName, BadgeName, Class, Date
    from RecursiveUserBadges
    where BadgeRank <= 3
),
UserPostsCTE as (
    select 
        p.Id, p.PostTypeId, p.ParentId, p.AcceptedAnswerId, p.OwnerUserId,
        p.CreationDate, p.Score, p.ViewCount,
        coalesce(p.Title, '') as Title,
        -- Extract first 3 tags from Tags string (if any)
        string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><') as TagArray
    from Posts p
    where p.PostTypeId in (1, 2) -- Questions and Answers
),
AnswerScores as (
    select 
        p.ParentId as QuestionId,
        avg(p.Score) as AvgAnswerScore,
        count(*) as AnswerCount
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        array_to_string(coalesce(q.TagArray, '{}'), ', ') as Tags,
        a.AvgAnswerScore,
        a.AnswerCount,
        -- Find if question is closed by checking posthistory type 10 (Post Closed)
        max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as IsClosed
    from UserPostsCTE q
    left join AnswerScores a on q.Id = a.QuestionId
    left join PostHistory ph on ph.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId, q.TagArray, a.AvgAnswerScore, a.AnswerCount
),
TopEngagedQuestions as (
    select 
        q.*,
        u.DisplayName as OwnerName,
        -- Calculate engagement score by weighted sum, complicated predicate with NULL logic
        (coalesce(q.AnswerCount, 0) * 5 + coalesce(q.ViewCount, 0) / 100 + coalesce(q.QuestionScore, 0)*2) as EngagementScore,
        row_number() over (order by (coalesce(q.AnswerCount, 0) * 5 + coalesce(q.ViewCount, 0)/100 + coalesce(q.QuestionScore, 0)*2) desc) as EngagementRank
    from QuestionDetails q
    left join Users u on u.Id = q.OwnerUserId
    where coalesce(q.IsClosed, 0) = 0
),
TopAnswersCTE as (
    select 
        a.Id,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as AnswererName,
        -- Lag window for previous answer score for same question
        lag(a.Score) over (partition by a.ParentId order by a.Score desc) as PrevAnswerScore,
        lead(a.Score) over (partition by a.ParentId order by a.Score desc) as NextAnswerScore
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
AnswerImprovement as (
    select 
        QuestionId,
        count(case when (Score > coalesce(PrevAnswerScore, -999999)) then 1 end) as ImprovingAnswers,
        count(case when (Score < coalesce(PrevAnswerScore, 999999)) then 1 end) as DecliningAnswers
    from TopAnswersCTE
    group by QuestionId
),
UserActiveHours as (
    select
        u.Id as UserId,
        date_part('hour', u.LastAccessDate) as HourOfDay,
        count(*) as AccessCount,
        rank() over (partition by u.Id order by count(*) desc) as RankByAccess
    from Users u
    group by u.Id, date_part('hour', u.LastAccessDate)
),
PopularHours as (
    select UserId, HourOfDay from UserActiveHours where RankByAccess = 1
),
ComplexUserSummary as (
    select 
        u.Id,
        u.DisplayName,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotesReceived,
        phCounts.EditsMade,
        phCounts.ClosuresMade,
        phLast.EditLastDate,
        phFirst.EditFirstDate,
        phFirst.EditFirstDate is null as HasNoEdits,
        pCounts.PostsCount
    from Users u
    left join (
        select UserId, count(1) as BadgeCount 
        from Badges 
        group by UserId
    ) b on u.Id = b.UserId
    left join Votes v on v.UserId = u.Id
    left join (
        select UserId, 
            count(case when PostHistoryTypeId in (4,5,6) then 1 end) as EditsMade,
            count(case when PostHistoryTypeId = 10 then 1 end) as ClosuresMade
        from PostHistory
        group by UserId
    ) phCounts on phCounts.UserId = u.Id
    left join (
        select UserId, min(CreationDate) as EditFirstDate, max(CreationDate) as EditLastDate
        from PostHistory
        group by UserId
    ) phFirst on phFirst.UserId = u.Id
    left join (
        select OwnerUserId, count(*) as PostsCount
        from Posts
        group by OwnerUserId
    ) pCounts on pCounts.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, b.BadgeCount, phCounts.EditsMade, phCounts.ClosuresMade, phLast.EditLastDate, phFirst.EditFirstDate, pCounts.PostsCount
),
FinalQuery as (
    select
        q.EngagementRank, q.QuestionId, q.Title, q.Tags, q.AnswerCount, q.ViewCount, q.QuestionScore, q.AvgAnswerScore,
        q.OwnerName,
        ai.ImprovingAnswers, ai.DecliningAnswers,
        cu.DisplayName as UserDisplayName,
        cu.BadgeCount, cu.UpVotesReceived, cu.DownVotesReceived, cu.EditsMade, cu.ClosuresMade,
        cu.EditFirstDate, cu.EditLastDate, cu.HasNoEdits, cu.PostsCount,
        ph.PostHistoryTypeId,
        lt.Name as LinkTypeName,
        -- Complex string and NULL logic involving post body and comments
        case 
            when length(p.Body) > 200 then substring(p.Body from 1 for 200) || '...'
            when p.Body is null then '[no body]'
            else p.Body end as SnippetBody,
        coalesce(cmt.TotalComments, 0) as TotalComments,
        coalesce(cmt.UniqueCommenters, 0) as UniqueCommenters,
        -- Window function: running total of views over questions ordered by EngagementScore
        sum(q.ViewCount) over (order by q.EngagementScore desc rows between unbounded preceding and current row) as CumulativeViews,
        -- Correlated subquery with EXISTS and NOT EXISTS for additional logic
        exists (
            select 1 
            from PostLinks pl 
            where pl.PostId = q.QuestionId 
            and pl.LinkTypeId = 3
        ) as HasDuplicates,
        not exists (
            select 1
            from Votes v2
            where v2.PostId = q.QuestionId AND v2.VoteTypeId = 4 -- Offensive votes
        ) as HasNoOffensiveVotes
    from TopEngagedQuestions q
    left join AnswerImprovement ai on ai.QuestionId = q.QuestionId
    left join ComplexUserSummary cu on cu.DisplayName = q.OwnerName
    left join Posts p on p.Id = q.QuestionId
    left join (
        select PostId, count(*) as TotalComments, count(distinct UserId) as UniqueCommenters
        from Comments
        group by PostId
    ) cmt on cmt.PostId = q.QuestionId
    left join PostLinks pl2 on pl2.PostId = q.QuestionId
    left join LinkTypes lt on lt.Id = pl2.LinkTypeId
    left join PostHistory ph on ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10 -- closed status
    where q.EngagementRank <= 50
)
select * from FinalQuery
order by EngagementRank;