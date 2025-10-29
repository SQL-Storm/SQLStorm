-- {"query": "2979.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1610}
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        p.OwnerUserId,
        p.Score,
        p.CreationDate
    from Posts p
    where p.PostTypeId = 1
),
UserTagStats as (
    select
        rt.OwnerUserId as UserId,
        rt.Tag,
        count(distinct rt.PostId) as QuestionsAsked,
        sum(rt.Score) as TotalScore,
        avg(rt.Score) as AvgScore,
        max(rt.Score) as MaxScore,
        min(rt.Score) as MinScore,
        count(distinct a.Id) as AnswersGiven,
        sum(a.Score) as AnswersScore,
        row_number() over (partition by rt.OwnerUserId order by count(distinct rt.PostId) desc) as TagRank
    from RecursiveTagCounts rt
    left join Posts a on a.ParentId = rt.PostId and a.PostTypeId = 2
    group by rt.OwnerUserId, rt.Tag
),
BadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
LatestPostHistory as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
UserLastAccess as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges
    from Users u
    left join BadgeCounts bc on u.Id = bc.UserId
),
TopTagsPerUser as (
    select
        uts.UserId,
        uts.Tag,
        uts.QuestionsAsked,
        uts.TotalScore,
        uts.AvgScore,
        uts.MaxScore,
        uts.MinScore,
        uts.AnswersGiven,
        coalesce(uts.AnswersScore, 0) as AnswersScore
    from UserTagStats uts
    where uts.TagRank <= 3
),
HighlyActiveUsers as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        sum(p.Score) as TotalPostScore,
        count(p.Id) as TotalPosts,
        max(p.LastActivityDate) as LastPostActivity
    from UserLastAccess u
    join Posts p on p.OwnerUserId = u.UserId
    where p.CreationDate > (cast('2024-10-01' as date) - interval '1 year')
    group by u.UserId, u.DisplayName, u.Reputation, u.GoldBadges, u.SilverBadges, u.BronzeBadges
    having count(p.Id) > 50
),
QuestionsWithDuplicateLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        p.Title as QuestionTitle,
        dup.Title as DuplicateTitle,
        p.Score as QuestionScore,
        dup.Score as DuplicateScore
    from PostLinks pl
    inner join Posts p on p.Id = pl.PostId and p.PostTypeId = 1
    inner join Posts dup on dup.Id = pl.RelatedPostId and dup.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserCommentStats as (
    select
        c.UserId,
        count(c.Id) as CommentCount,
        sum(c.Score) as CommentScore,
        avg(c.Score) as AvgCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
FinalResultSet as (
    select
        hau.UserId,
        hau.DisplayName,
        hau.Reputation,
        hau.GoldBadges,
        hau.SilverBadges,
        hau.BronzeBadges,
        hau.TotalPosts,
        hau.TotalPostScore,
        hau.LastPostActivity,
        uts.Tag,
        uts.QuestionsAsked,
        uts.TotalScore as TagTotalScore,
        uts.AvgScore as TagAvgScore,
        uts.MaxScore as TagMaxScore,
        uts.MinScore as TagMinScore,
        uts.AnswersGiven,
        uts.AnswersScore,
        coalesce(ucs.CommentCount, 0) as CommentCount,
        coalesce(ucs.CommentScore, 0) as CommentScore,
        coalesce(ucs.AvgCommentScore, 0) as AvgCommentScore,
        u.LastAccessDate
    from HighlyActiveUsers hau
    left join TopTagsPerUser uts on hau.UserId = uts.UserId
    left join UserCommentStats ucs on hau.UserId = ucs.UserId
    join Users u on u.Id = hau.UserId
)
select distinct
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.TotalPosts,
    fr.TotalPostScore,
    fr.LastPostActivity,
    fr.LastAccessDate,
    fr.Tag,
    fr.QuestionsAsked,
    fr.TagTotalScore,
    fr.TagAvgScore,
    fr.TagMaxScore,
    fr.TagMinScore,
    fr.AnswersGiven,
    fr.AnswersScore,
    fr.CommentCount,
    fr.CommentScore,
    fr.AvgCommentScore,
    concat_ws(' | ',
        'Badges: G=', fr.GoldBadges, 'S=', fr.SilverBadges, 'B=', fr.BronzeBadges,
        'Posts:', fr.TotalPosts, 'Score:', fr.TotalPostScore,
        'Comments:', fr.CommentCount, 'AvgCommentScore:', round(CAST(fr.AvgCommentScore AS numeric),2)
    ) as SummaryInfo,
    case when fr.TotalPostScore = 0 then null else CAST(fr.Reputation AS numeric) / fr.TotalPostScore end as ReputationPostScoreRatio,
    rank() over (order by fr.Reputation desc) as ReputationRank,
    (
        select count(distinct qdw.PostId)
        from QuestionsWithDuplicateLinks qdw
        where qdw.PostId in (select p.Id from Posts p where p.OwnerUserId = fr.UserId and p.PostTypeId = 1)
    ) as DuplicateCountLinked,
    case when fr.LastPostActivity > (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') then true else false end as IsRecentlyActive,
    case when fr.GoldBadges > 0 and fr.LastPostActivity > (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') then 'Elite' else 'Standard' end as UserCategory
from FinalResultSet fr
order by ReputationRank, fr.TagTotalScore desc
limit 100;