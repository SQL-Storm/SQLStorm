-- {"query": "2137.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1667} 
with RecursiveUserHierarchy as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        1 as Level,
        null::int as ManagerId
    from Users u 
    where u.Id = (select min(Id) from Users)
    union all
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        ruh.Level + 1,
        ruh.Id
    from Users u
    join RecursiveUserHierarchy ruh on u.Id > ruh.Id
    where ruh.Level < 5
),
TopScoringAnswerForRecentQuestions as (
    select p.Id as QuestionId, p.Title, p.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        row_number() over(partition by p.Id order by a.Score desc, a.CreationDate asc) as rn
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '90 days'
),
UserBadgeStats as (
    select b.UserId, 
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserEngagement as (
    select u.Id, u.DisplayName, 
        coalesce(sum(p.ViewCount),0) as TotalViews,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(count(c.Id),0) as TotalComments,
        coalesce(sum(v.VoteTypeId = 2::smallint::int),0) as UpVotesReceived,
        coalesce(sum(v.VoteTypeId = 3::smallint::int),0) as DownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionsWithComplexPredicates as (
    select p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate,
        array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'),1) as TagCount,
        case 
            when p.Score > 10 and p.ViewCount > 1000 then 'Hot'
            when p.Score between 5 and 10 then 'Trending'
            else 'Regular'
        end as PopularityStatus,
        exists (
            select 1 from Votes v2 where v2.PostId = p.Id and v2.VoteTypeId = 5 and v2.CreationDate > current_date - interval '30 days'
        ) as HasRecentFavorite,
        coalesce(p.AnswerCount,0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
),
DuplicatesAndLinkedPosts as (
    select distinct pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name in ('Linked','Duplicate')
),
QuestionCloseReasonStats as (
    select cht.Name as CloseReason, count(*) as ClosedCount
    from PostHistory ph
    join PostHistoryTypes chtp on ph.PostHistoryTypeId = chtp.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
    order by ClosedCount desc
),
RankedAnswersWithWindow as (
    select a.Id, a.ParentId as QuestionId, a.Score, 
        rank() over(partition by a.ParentId order by a.Score desc) as ScoreRank,
        dense_rank() over(partition by a.ParentId order by a.CreationDate asc) as OldestRank
    from Posts a
    where a.PostTypeId = 2
),
AnswerToQuestionCorrelation as (
    select q.Id as QuestionId, q.Title, a.Id as AnswerId, a.Score as AnswerScore,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerComments,
        (select max(p.Score) from Posts p where p.ParentId = q.Id and p.PostTypeId = 2) as MaxAnswerScore,
        q.AnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
FinalAggregate as (
    select
        u.Id as UserId,
        u.DisplayName,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        ue.TotalViews,
        ue.TotalPostScore,
        ue.TotalComments,
        ue.UpVotesReceived,
        ue.DownVotesReceived,
        q.PopularityStatus,
        q.TagCount,
        q.HasRecentFavorite,
        q.AnswerCount,
        qc.ClosedCount,
        max(r.ScoreRank) filter (where r.ScoreRank <= 3) as Top3AnswerRank,
        avg(r.Score) filter (where r.ScoreRank <= 3) as AvgTop3AnswerScore,
        sum(case when r.ScoreRank = 1 then 1 else 0 end) as FirstRankCount
    from Users u
    left join UserBadgeStats us on us.UserId = u.Id
    left join UserEngagement ue on ue.Id = u.Id
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join QuestionsWithComplexPredicates q on q.Id = p.Id
    left join QuestionCloseReasonStats qc on 1=1
    left join RankedAnswersWithWindow r on r.QuestionId = p.Id
    group by u.Id, u.DisplayName, us.GoldBadges, us.SilverBadges, us.BronzeBadges, ue.TotalViews, ue.TotalPostScore, ue.TotalComments, ue.UpVotesReceived, ue.DownVotesReceived, q.PopularityStatus, q.TagCount, q.HasRecentFavorite, q.AnswerCount, qc.ClosedCount
    having coalesce(us.GoldBadges, 0) + coalesce(us.SilverBadges, 0) + coalesce(us.BronzeBadges, 0) > 0
)
select 
    fa.UserId,
    fa.DisplayName,
    fa.GoldBadges, fa.SilverBadges, fa.BronzeBadges,
    fa.TotalViews, fa.TotalPostScore, fa.TotalComments,
    fa.UpVotesReceived, fa.DownVotesReceived,
    fa.PopularityStatus, fa.TagCount, fa.HasRecentFavorite, fa.AnswerCount,
    fa.ClosedCount,
    fa.Top3AnswerRank, fa.AvgTop3AnswerScore, fa.FirstRankCount,
    case when fa.TotalPostScore > 0 then (fa.UpVotesReceived - fa.DownVotesReceived)::float/fa.TotalPostScore else null end as UpDownRatio,
    case when fa.TagCount > 0 then fa.TotalViews/fa.TagCount else null end as ViewsPerTag
from FinalAggregate fa
where fa.TotalViews > 1000 and fa.AvgTop3AnswerScore is not null and fa.Top3AnswerRank is not null
order by fa.GoldBadges desc nulls last, fa.AvgTop3AnswerScore desc nulls last, fa.TotalViews desc nulls last
limit 100;