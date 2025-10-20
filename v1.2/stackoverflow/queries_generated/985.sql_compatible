with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.ViewCount,0) as PostView,
        coalesce(p.Score,0) as PostScore,
        row_number() over (partition by t.Id order by p.Score desc) as rn
    from Tags t
    left join Posts p 
        on p.Tags like ('%' || '<' || t.TagName || '>' || '%')
        and p.PostTypeId = 1
),
TopPostsPerTag as (
    select TagId, TagName, PostView, PostScore
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeAggregates as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as RecentBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostLinkDuplicates as (
    select DISTINCT pl.PostId, pl.RelatedPostId
    from PostLinks pl
    where pl.LinkTypeId = 3
),
LatestPostHistory as (
    select ph.PostId, max(ph.CreationDate) as LastHistoryChangeDate
    from PostHistory ph
    group by ph.PostId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when exists (
            select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 1
        ) then 1 else 0 end) as AcceptedCount
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionDetails as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        coalesce(a.AnswerCount,0) as AnswerCount,
        coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(a.AcceptedCount,0) as AcceptedAnswers,
        coalesce(pl.RelatedPostId, -1) as DuplicateOf,
        ph.LastHistoryChangeDate
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join AnswerStats a on a.QuestionId = q.Id
    left join PostLinkDuplicates pl on pl.PostId = q.Id
    left join LatestPostHistory ph on ph.PostId = q.Id
    where q.PostTypeId = 1
),
RankedQuestions as (
    select
        qd.Id,
        qd.Title,
        qd.Tags,
        qd.OwnerUserId,
        qd.OwnerDisplayName,
        qd.CreationDate,
        qd.Score,
        qd.ViewCount,
        qd.AnswerCount,
        qd.AvgAnswerScore,
        qd.MaxAnswerScore,
        qd.AcceptedAnswers,
        qd.DuplicateOf,
        qd.LastHistoryChangeDate,
        row_number() over (partition by qd.OwnerUserId order by qd.Score desc, qd.ViewCount desc) as UserTopQuestionRank,
        rank() over (order by qd.Score desc, qd.ViewCount desc) as GlobalRank
    from QuestionDetails qd
),
CorrelatedBadges as (
    select
        rq.Id as QuestionId,
        rq.Title,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.AvgAnswerScore,
        rq.MaxAnswerScore,
        rq.AcceptedAnswers,
        rq.DuplicateOf,
        rq.LastHistoryChangeDate,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.RecentBadgeDate,
        case 
            when ub.TotalBadges > 10 then 'Veteran'
            when ub.TotalBadges between 1 and 10 then 'Contributor'
            else 'Newbie'
        end as UserLevel,
        (select count(1) from Comments c where c.PostId = rq.Id and c.CreationDate > (rq.LastHistoryChangeDate - interval '30 days')) as RecentCommentsCount,
        (select string_agg(distinct vt.Name, ', ')
         from Votes v2
         join VoteTypes vt on vt.Id = v2.VoteTypeId
         where v2.PostId = rq.Id) as VoteTypeNames,
        rq.OwnerUserId,
        rq.UserTopQuestionRank,
        rq.GlobalRank
    from RankedQuestions rq
    left join UserBadgeAggregates ub on ub.UserId = rq.OwnerUserId
)
select 
    cb.QuestionId,
    substring(cb.Title from 1 for 100) as TitleSample,
    cb.Score,
    cb.ViewCount,
    cb.AnswerCount,
    round(cast(cb.AvgAnswerScore as numeric),2) as AvgAnswerScore,
    cb.MaxAnswerScore,
    cb.AcceptedAnswers,
    cb.DuplicateOf,
    cb.LastHistoryChangeDate,
    cb.TotalBadges,
    cb.GoldBadges,
    cb.SilverBadges,
    cb.BronzeBadges,
    cb.RecentBadgeDate,
    cb.UserLevel,
    cb.RecentCommentsCount,
    coalesce(cb.VoteTypeNames,'NoVotes') as VoteTypes,
    (case
        when cb.Score > 50 then 'High Score' else 'Low Score' end
     || ' | ' ||
     case when cb.AnswerCount > 5 then 'Active Question' else 'Few Answers' end
     || ' | ' ||
     case when cb.DuplicateOf > 0 then 'Is Duplicate' else 'Original Question' end
    ) as StatusTags,
    cb.OwnerUserId,
    cb.UserTopQuestionRank,
    cb.GlobalRank
from CorrelatedBadges cb
where cb.GlobalRank <= 100
group by
    cb.QuestionId,
    cb.Title,
    cb.Score,
    cb.ViewCount,
    cb.AnswerCount,
    cb.AvgAnswerScore,
    cb.MaxAnswerScore,
    cb.AcceptedAnswers,
    cb.DuplicateOf,
    cb.LastHistoryChangeDate,
    cb.TotalBadges,
    cb.GoldBadges,
    cb.SilverBadges,
    cb.BronzeBadges,
    cb.RecentBadgeDate,
    cb.UserLevel,
    cb.RecentCommentsCount,
    cb.VoteTypeNames,
    cb.OwnerUserId,
    cb.UserTopQuestionRank,
    cb.GlobalRank
order by cb.Score desc, cb.ViewCount desc;