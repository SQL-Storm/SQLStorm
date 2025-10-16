-- {"query": "264.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2013} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as QuestionAnswerCount,
        coalesce(p.ViewCount, 0) as QuestionViewCount,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsModeratorOnly = 0
),
FilteredTags as (
    select TagId, TagName, Count, QuestionAnswerCount, QuestionViewCount
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeAgg as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserActivityWindow as (
    select
        UserId,
        DisplayName,
        QuestionCount,
        AnswerCount,
        TotalPostScore,
        LastPostDate,
        FirstPostDate,
        AvgPostScore,
        row_number() over (order by TotalPostScore desc nulls last) as RankByScore,
        rank() over (partition by AnswerCount > QuestionCount order by TotalPostScore desc nulls last) as RankByScorePartition
    from UserPostStats
),
TopUsers as (
    select *
    from UserActivityWindow
    where RankByScore <= 100
),
PostWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(v.Favorites,0) as Favorites
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes,
            sum(case when VoteTypeId = 5 then 1 else 0 end) as Favorites
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.PostTypeId as PostTypeId,
        p2.PostTypeId as RelatedPostTypeId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
ComplexPostAnalysis as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.UpVotes,
        p.DownVotes,
        p.Favorites,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeName = 'Duplicate') as DuplicateLinksCount,
        count(distinct pl.RelatedPostId) filter (where pl.LinkTypeName = 'Linked') as LinkedPostsCount,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRankByScore,
        dense_rank() over (order by p.Score desc nulls last) as GlobalPostRankByScore,
        length(coalesce(p.Body, '')) as BodyLength,
        strpos(coalesce(p.Tags, ''), 'sql') > 0 as HasSqlTag,
        strpos(coalesce(p.Tags, ''), 'performance') > 0 as HasPerformanceTag
    from PostWithVotes p
    left join PostLinkDetails pl on pl.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.Tags, p.UpVotes, p.DownVotes, p.Favorites, p.AcceptedAnswerId, p.Body
),
UserPostSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalQuestions,
        sum(case when p.HasAcceptedAnswer = 1 then 1 else 0 end) as QuestionsWithAcceptedAnswer,
        avg(p.Score) as AvgQuestionScore,
        sum(p.DuplicateLinksCount) as TotalDuplicateLinks,
        sum(p.LinkedPostsCount) as TotalLinkedPosts,
        max(p.GlobalPostRankByScore) as MaxGlobalPostRank,
        sum(case when p.HasSqlTag then 1 else 0 end) as SqlTaggedQuestions,
        sum(case when p.HasPerformanceTag then 1 else 0 end) as PerformanceTaggedQuestions
    from Users u
    left join ComplexPostAnalysis p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserBadgeAndPostStats as (
    select
        ups.UserId,
        ups.DisplayName,
        ups.TotalQuestions,
        ups.QuestionsWithAcceptedAnswer,
        ups.AvgQuestionScore,
        ups.TotalDuplicateLinks,
        ups.TotalLinkedPosts,
        ups.MaxGlobalPostRank,
        ups.SqlTaggedQuestions,
        ups.PerformanceTaggedQuestions,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uba.DistinctBadges
    from UserPostSummary ups
    left join UserBadgeAgg uba on uba.UserId = ups.UserId
),
FinalResult as (
    select
        ubps.UserId,
        ubps.DisplayName,
        ubps.TotalQuestions,
        ubps.QuestionsWithAcceptedAnswer,
        ubps.AvgQuestionScore,
        ubps.TotalDuplicateLinks,
        ubps.TotalLinkedPosts,
        ubps.MaxGlobalPostRank,
        ubps.SqlTaggedQuestions,
        ubps.PerformanceTaggedQuestions,
        ubps.GoldBadges,
        ubps.SilverBadges,
        ubps.BronzeBadges,
        ubps.DistinctBadges,
        case
            when ubps.TotalQuestions = 0 then null
            else round(100.0 * ubps.QuestionsWithAcceptedAnswer / ubps.TotalQuestions, 2)
        end as AcceptedAnswerRatePercent,
        case
            when ubps.TotalQuestions = 0 then null
            else round(ubps.AvgQuestionScore / ubps.TotalQuestions, 2)
        end as AvgScorePerQuestion,
        case
            when ubps.TotalQuestions = 0 then null
            else round(ubps.SqlTaggedQuestions * 100.0 / ubps.TotalQuestions, 2)
        end as SqlTagPercent,
        case
            when ubps.TotalQuestions = 0 then null
            else round(ubps.PerformanceTaggedQuestions * 100.0 / ubps.TotalQuestions, 2)
        end as PerformanceTagPercent
    from UserBadgeAndPostStats ubps
    where ubps.TotalQuestions > 10
    order by AcceptedAnswerRatePercent desc nulls last, AvgScorePerQuestion desc nulls last
    limit 50
)
select
    fr.UserId,
    fr.DisplayName,
    fr.TotalQuestions,
    fr.QuestionsWithAcceptedAnswer,
    fr.AcceptedAnswerRatePercent,
    fr.AvgQuestionScore,
    fr.AvgScorePerQuestion,
    fr.TotalDuplicateLinks,
    fr.TotalLinkedPosts,
    fr.MaxGlobalPostRank,
    fr.SqlTagPercent,
    fr.PerformanceTagPercent,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.DistinctBadges
from FinalResult fr
union
select
    u.Id,
    u.DisplayName,
    0,
    0,
    null,
    0,
    null,
    0,
    0,
    null,
    null,
    null,
    0,
    0,
    0,
    0
from Users u
where not exists (
    select 1 from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1
)
order by TotalQuestions desc nulls last, DisplayName
limit 100;