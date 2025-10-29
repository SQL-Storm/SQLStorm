-- {"query": "2560.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1383} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
TopBadgeUsers as (
    select UserId, DisplayName, BadgeName, Class from RecursiveUserBadges where BadgeRank <= 3
),
PostRelations as (
    select 
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        pt.Name as PostTypeName,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        case when p.Score is null then 0 else p.Score end as Score
    from Posts p
    left join PostTypes pt on p.PostTypeId = pt.Id
    left join PostLinks pl on p.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
),
AnswerScores as (
    select 
        p.ParentId as QuestionId,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        count(*) as AnswerCount
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as NumPosts,
        sum(p.Score) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        avg(case when p.PostTypeId = 1 then p.ViewCount else null end) as AvgQuestionViews
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id, u.DisplayName
),
CloseReasonsCount as (
    select 
        p.OwnerUserId as UserId,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as NumClosedPosts,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as NumReopenedPosts
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId
    group by p.OwnerUserId
),
CTE_QuestionsWithHotness as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        ascore.AvgAnswerScore,
        ascore.MaxAnswerScore,
        rank() over (order by q.ViewCount desc, q.Score desc) as ViewRank,
        dense_rank() over (partition by substring(q.Tags from 2 for (length(q.Tags) - 2)) order by q.Score desc) as ScoreRankPerTag
    from Posts q
    left join AnswerScores ascore on q.Id = ascore.QuestionId
    where q.PostTypeId = 1
),
ComplexQuery as (
    select
        u.Id as UserId,
        u.DisplayName,
        ua.NumPosts,
        ua.TotalPostScore,
        cr.NumClosedPosts,
        cr.NumReopenedPosts,
        tb.BadgeName,
        tb.Class as BadgeClass,
        q.QuestionId,
        q.Title as QuestionTitle,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        coalesce(q.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(q.MaxAnswerScore,0) as MaxAnswerScore,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        count(distinct c.Id) as CommentCountOnQuestions,
        string_agg(distinct coalesce(lt.Name,'NoLink'), ',') as LinkTypesForUserPosts,
        row_number() over (partition by u.Id order by q.Score desc, q.ViewCount desc) as UserTopQuestionRank
    from Users u
    left join UserActivity ua on u.Id = ua.Id
    left join CloseReasonsCount cr on u.Id = cr.UserId
    left join TopBadgeUsers tb on u.Id = tb.UserId
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join CTE_QuestionsWithHotness q on q.QuestionId = p.Id
    left join Comments c on c.PostId = p.Id
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where u.Reputation > 1000 
      and (tb.Class is null or tb.Class <= 2) -- at most Silver badge considered
      and q.ViewCount > 1000
    group by
        u.Id, u.DisplayName, ua.NumPosts, ua.TotalPostScore, cr.NumClosedPosts, cr.NumReopenedPosts,
        tb.BadgeName, tb.Class, q.QuestionId, q.Title, q.Score, q.ViewCount, q.AvgAnswerScore, q.MaxAnswerScore, q.AcceptedAnswerId
)
select 
    UserId,
    DisplayName,
    NumPosts,
    TotalPostScore,
    NumClosedPosts,
    NumReopenedPosts,
    BadgeName,
    BadgeClass,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViews,
    AvgAnswerScore,
    MaxAnswerScore,
    HasAcceptedAnswer,
    CommentCountOnQuestions,
    LinkTypesForUserPosts
from ComplexQuery
where UserTopQuestionRank <= 5
order by TotalPostScore desc, QuestionViews desc, UserId
union
select 
    u.Id as UserId,
    u.DisplayName,
    ua.NumPosts,
    ua.TotalPostScore,
    cr.NumClosedPosts,
    cr.NumReopenedPosts,
    null as BadgeName,
    null as BadgeClass,
    null as QuestionId,
    null as QuestionTitle,
    null as QuestionScore,
    null as QuestionViews,
    null as AvgAnswerScore,
    null as MaxAnswerScore,
    null as HasAcceptedAnswer,
    0 as CommentCountOnQuestions,
    '' as LinkTypesForUserPosts
from Users u
left join UserActivity ua on u.Id = ua.Id
left join CloseReasonsCount cr on u.Id = cr.UserId
where u.Reputation > 1000
  and u.Id not in (select distinct UserId from ComplexQuery)
limit 20;