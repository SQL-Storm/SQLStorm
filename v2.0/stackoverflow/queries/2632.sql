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
        -- convert tag string like '<tag1><tag2>' into an array by removing leading/trailing angle brackets and splitting on '><'
        case 
          when p.Tags is null then null
          else regexp_split_to_array(substr(p.Tags, 2, greatest(length(p.Tags) - 2, 0)), '><')
        end as TagArray
    from Posts p
    where p.PostTypeId in (1, 2)
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
        -- convert array to string in a more portable way
        case when q.TagArray is null then '' else array_to_string(q.TagArray, ', ') end as Tags,
        a.AvgAnswerScore,
        a.AnswerCount,
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
        (coalesce(q.AnswerCount, 0) * 5 + coalesce(q.ViewCount, 0) / 100.0 + coalesce(q.QuestionScore, 0)*2) as EngagementScore,
        row_number() over (order by (coalesce(q.AnswerCount, 0) * 5 + coalesce(q.ViewCount, 0)/100.0 + coalesce(q.QuestionScore, 0)*2) desc) as EngagementRank
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
        extract(hour from u.LastAccessDate) as HourOfDay,
        count(*) as AccessCount,
        rank() over (partition by u.Id order by count(*) desc) as RankByAccess
    from Users u
    group by u.Id, extract(hour from u.LastAccessDate)
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
        phFirst.EditLastDate,
        phFirst.EditFirstDate,
        (phFirst.EditFirstDate is null) as HasNoEdits,
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
    group by u.Id, u.DisplayName, b.BadgeCount, phCounts.EditsMade, phCounts.ClosuresMade, phFirst.EditLastDate, phFirst.EditFirstDate, pCounts.PostsCount
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
        case 
            when p.Body is not null and length(p.Body) > 200 then substring(p.Body from 1 for 200) || '...'
            when p.Body is null then '[no body]'
            else p.Body end as SnippetBody,
        coalesce(cmt.TotalComments, 0) as TotalComments,
        coalesce(cmt.UniqueCommenters, 0) as UniqueCommenters,
        sum(q.ViewCount) over (order by q.EngagementScore desc rows between unbounded preceding and current row) as CumulativeViews,
        exists (
            select 1 
            from PostLinks pl 
            where pl.PostId = q.QuestionId 
            and pl.LinkTypeId = 3
        ) as HasDuplicates,
        not exists (
            select 1
            from Votes v2
            where v2.PostId = q.QuestionId AND v2.VoteTypeId = 4
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
    left join PostHistory ph on ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10
    where q.EngagementRank <= 50
)
select * from FinalQuery
order by EngagementRank;