with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date > u.CreationDate
),
TopBadges as (
    select UserId, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        coalesce(a.AcceptedAnswerId, -1) as AcceptedAnswerId,
        coalesce(a.AnswerCount, 0) as TotalAnswers,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCount, max(Id) as AcceptedAnswerId
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on p.Id = a.ParentId
    where p.PostTypeId = 1
),
AnswerVotes as (
    select 
        p.ParentId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(distinct v.UserId) as UniqueVoters
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivityRank as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        row_number() over (order by count(distinct p.Id) desc, count(distinct c.Id) desc) as ActivityRank
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    group by u.Id, u.DisplayName
),
ClosedQuestionsWithReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo as (
    select 
        qs.*,
        cqr.CloseReason,
        cqr.CloseDate
    from QuestionStats qs
    left join ClosedQuestionsWithReasons cqr on qs.QuestionId = cqr.PostId
),
TagExploded as (
    select 
        QuestionId,
        trim(t) as Tag
    from (
        select
            QuestionId,
            regexp_split_to_table(
                substring(Tags from 2 for (length(Tags) - 2)),
                '><'
            ) as t
        from QuestionStats
    ) s
),
TagRankings as (
    select 
        Tag,
        count(*) as QuestionCount,
        avg(qs.Score) as AvgScore,
        rank() over (order by count(*) desc) as TagPopularityRank
    from TagExploded te
    left join QuestionStats qs on te.QuestionId = qs.QuestionId
    group by Tag
),
CombinedResults as (
    select 
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        av.UpVotes,
        av.DownVotes,
        av.UniqueVoters,
        q.IsClosed,
        q.CloseReason,
        q.CloseDate,
        string_agg(distinct tb.BadgeName || ' (' || case tb.Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')', ', ') as TopBadges,
        tar.Tag as PopularTag,
        tar.QuestionCount as PopularTagQuestionCount,
        tar.AvgScore as PopularTagAvgScore,
        tar.TagPopularityRank,
        uar.ActivityRank
    from QuestionsWithCloseInfo q
    left join Users u on q.OwnerUserId = u.Id
    left join AnswerVotes av on q.QuestionId = av.QuestionId
    left join TopBadges tb on tb.UserId = q.OwnerUserId
    left join TagExploded te on q.QuestionId = te.QuestionId
    left join TagRankings tar on te.Tag = tar.Tag
    left join UserActivityRank uar on uar.Id = q.OwnerUserId
    group by 
        q.QuestionId, q.Title, q.OwnerUserId, u.DisplayName, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount,
        av.UpVotes, av.DownVotes, av.UniqueVoters, q.IsClosed, q.CloseReason, q.CloseDate,
        tar.Tag, tar.QuestionCount, tar.AvgScore, tar.TagPopularityRank,
        uar.ActivityRank
)
select 
    cr.*,
    case 
        when cr.IsClosed = 1 and cr.CloseDate < cr.CreationDate + interval '30 days' then 'Closed Quickly'
        when cr.IsClosed = 1 then 'Closed Late'
        else 'Open'
    end as ClosureSpeed,
    length(cr.Title) as TitleLength,
    coalesce(cr.ViewCount,0) / nullif(cr.AnswerCount,0) as ViewsPerAnswer,
    case when cr.Score > 0 then cr.Score * ln(1 + cr.ViewCount) else 0 end as WeightedScore,
    upper(cr.PopularTag) as PopularTagUpper,
    coalesce(cr.TopBadges, 'No Badges') as UserBadgesSummary,
    cr.ActivityRank,
    dense_rank() over (order by case when cr.Score > 0 then cr.Score * ln(1 + cr.ViewCount) else 0 end desc) as ScoreRank
from CombinedResults cr
where cr.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
  and cr.PopularTag is not null
  and cr.ActivityRank <= 100
order by ScoreRank
limit 100;