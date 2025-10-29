with RecursiveBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveBadges
    where BadgeRank <= 3
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score), 0) as TotalAnswerScore,
        max(case when a.Id = q.AcceptedAnswerId then a.Score else null end) as AcceptedAnswerScore,
        q.AcceptedAnswerId
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.Score, q.ViewCount, q.AcceptedAnswerId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when ph.PostHistoryTypeId in (1,4,5,6) then ph.PostId end) as EditsCount,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.PostId end) as CloseVotesCount,
        count(distinct case when ph.PostHistoryTypeId = 11 then ph.PostId end) as ReopenVotesCount,
        row_number() over (partition by u.Id order by u.CreationDate) as UserSeq,
        u.CreationDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    where u.Reputation > 500
    group by u.Id, u.DisplayName, u.CreationDate
),
RecentHotQuestions as (
    select distinct pht.PostId
    from PostHistory pht
    join PostHistoryTypes phtt on pht.PostHistoryTypeId = phtt.Id
    where pht.PostHistoryTypeId = 52
      and pht.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
),
QuestionsWithComments as (
    select
        q.Id as QuestionId,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Posts q
    left join Comments c on c.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(*) filter (where lt.Name = 'Linked') as LinkedCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
)
select
    q.QuestionId,
    q.Title,
    q.QuestionDate,
    q.ViewCount,
    q.QuestionScore,
    q.AnswerCount,
    q.TotalAnswerScore,
    q.AcceptedAnswerScore,
    coalesce(ql.DuplicateCount, 0) as DuplicateLinks,
    coalesce(ql.LinkedCount, 0) as LinkedPosts,
    coalesce(qc.CommentCount, 0) as QuestionComments,
    qc.Commenters,
    tb.BadgeName,
    case tb.Class
        when 1 then 'Gold'
        when 2 then 'Silver'
        when 3 then 'Bronze'
        else 'Unknown'
    end as BadgeClass,
    ua.EditsCount,
    ua.CloseVotesCount,
    ua.ReopenVotesCount,
    ua.UserSeq,
    case
        when q.ViewCount > 10000 and q.QuestionScore > 50 then 'HighPopularity'
        when q.AnswerCount > 10 and q.TotalAnswerScore > 100 then 'HighlyEngaged'
        else 'Normal'
    end as PopularityCategory,
    case when rhq.PostId is not null then true else false end as IsHotQuestion,
    (select ph2.UserDisplayName
     from PostHistory ph2
     where ph2.PostId = q.QuestionId
       and ph2.PostHistoryTypeId in (4,5,6)
     order by ph2.CreationDate desc
     limit 1) as LastEditorName,
    concat_ws(' | ',
        q.Title,
        coalesce(ua.DisplayName, 'No Owner'),
        coalesce(tb.BadgeName, 'No Badge'),
        coalesce(qc.Commenters, 'No Comments')
    ) as SummaryString
from QuestionsWithAnswers q
left join DuplicateLinkCounts ql on q.QuestionId = ql.PostId
left join QuestionsWithComments qc on q.QuestionId = qc.QuestionId
left join TopBadges tb on tb.UserId = q.OwnerUserId
left join UserActivityWindow ua on ua.UserId = q.OwnerUserId
left join RecentHotQuestions rhq on rhq.PostId = q.QuestionId
where q.QuestionDate > cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  and (q.QuestionScore is not null and q.ViewCount is not null)
  and (tb.BadgeName is not null or ua.EditsCount > 5)
group by
    q.QuestionId,
    q.Title,
    q.QuestionDate,
    q.ViewCount,
    q.QuestionScore,
    q.AnswerCount,
    q.TotalAnswerScore,
    q.AcceptedAnswerScore,
    ql.DuplicateCount,
    ql.LinkedCount,
    qc.CommentCount,
    qc.Commenters,
    tb.BadgeName,
    tb.Class,
    ua.EditsCount,
    ua.CloseVotesCount,
    ua.ReopenVotesCount,
    ua.UserSeq,
    rhq.PostId,
    ua.DisplayName
order by PopularityCategory desc, q.ViewCount desc, q.QuestionScore desc
limit 100;