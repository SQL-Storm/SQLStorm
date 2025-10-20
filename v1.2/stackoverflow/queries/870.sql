with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagAggregates as (
    select
        Tag,
        count(*) as QuestionCount,
        avg(Score) as AvgScore,
        sum(ViewCount) as TotalViews,
        max(CreationDate) as LatestQuestionDate
    from RecursiveTagCounts
    group by Tag
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(u.Reputation) over () as TotalReputationAcrossUsers,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation
),
PostLinksCount as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinks,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        coalesce(plc.DuplicateLinks, 0) as DuplicateLinks,
        coalesce(plc.LinkedPosts, 0) as LinkedPosts,
        u.DisplayName as OwnerDisplayName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join PostLinksCount plc on p.Id = plc.PostId
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
QuestionsWithBadges as (
    select
        tq.*,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.ReputationRank
    from TopQuestions tq
    left join UserBadgeStats ub on tq.OwnerUserId = ub.UserId
),
QuestionsWithCloseInfo as (
    select
        qb.*,
        ch.CloseReasonName,
        ch.ClosedCount
    from QuestionsWithBadges qb
    left join (
        select
            ph.PostId,
            crt.Name as CloseReasonName,
            count(*) as ClosedCount
        from PostHistory ph
        join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
        where pht.Name = 'Post Closed'
        group by ph.PostId, crt.Name
    ) ch on qb.Id = ch.PostId
),
RankedQuestions as (
    select
        rq.*,
        dense_rank() over (order by rq.Score desc) as ScoreRank,
        ntile(10) over (order by rq.ViewCount desc) as ViewCountDecile
    from QuestionsWithCloseInfo rq
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswerCount
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
FinalSelection as (
    select
        rq.Id as QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.OwnerDisplayName,
        rq.Score,
        rq.ViewCount,
        rq.Tags,
        rq.DuplicateLinks,
        rq.LinkedPosts,
        rq.GoldBadges,
        rq.SilverBadges,
        rq.BronzeBadges,
        rq.ReputationRank,
        rq.CloseReasonName,
        rq.ClosedCount,
        rq.ScoreRank,
        rq.ViewCountDecile,
        coalesce(ans.AnswerCount, 0) as AnswerCount,
        coalesce(ans.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(ans.AnonymousAnswerCount, 0) as AnonymousAnswerCount,
        ta.QuestionCount,
        ta.AvgScore as TagAvgScore,
        ta.TotalViews as TagTotalViews,
        ta.LatestQuestionDate
    from RankedQuestions rq
    left join AnswerStats ans on rq.Id = ans.QuestionId
    left join TagAggregates ta on ta.Tag = (
        select unnest(string_to_array(substring(rq.Tags from 2 for length(rq.Tags)-2), '><')) limit 1
    )
)
select
    fs.*,
    case
        when fs.CloseReasonName is not null then 'Closed: ' || fs.CloseReasonName
        else 'Open'
    end as PostStatus,
    case
        when (coalesce(fs.GoldBadges,0) + coalesce(fs.SilverBadges,0) + coalesce(fs.BronzeBadges,0)) >= 10 and fs.ReputationRank <= 100 then 'High Reputation Expert'
        when (coalesce(fs.GoldBadges,0) + coalesce(fs.SilverBadges,0) + coalesce(fs.BronzeBadges,0)) >= 5 then 'Intermediate Contributor'
        else 'New or Low Contributor'
    end as UserContributorLevel,
    concat_ws(' / ',
        'Score Rank: ' || fs.ScoreRank,
        'View Decile: ' || fs.ViewCountDecile,
        'Answers: ' || fs.AnswerCount,
        'Avg Answer Score: ' || round(fs.AvgAnswerScore, 2),
        'Tag Questions: ' || fs.QuestionCount,
        'Tag Avg Score: ' || round(fs.TagAvgScore, 2)
    ) as SummaryStats
from FinalSelection fs
where fs.AnswerCount > 5
  and (fs.ClosedCount is null or fs.ClosedCount = 0)
order by fs.ScoreRank, fs.ViewCount desc
limit 50;