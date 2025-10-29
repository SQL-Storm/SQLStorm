with recursive RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 0 as Level
    from Tags t
    where t.Count > 1000
  union all
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, r.Level + 1
    from Tags t
    inner join RecursiveTagHierarchy r on t.Id = r.Id - 1
    where r.Level < 2 and t.Count > 500
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then b.BadgeCount end),0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then b.BadgeCount end),0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then b.BadgeCount end),0) as BronzeBadges
    from Users u
    left join UserBadgeCounts b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
QuestionStats as (
    select
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1
),
AnswerStats as (
    select
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc) as AnswerRankForQuestion,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate asc) as AnswerSequenceNumber
    from Posts p
    where p.PostTypeId = 2
),
TopAnswersWithVotes as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        avg(case when v.VoteTypeId in (2,3) then 1.0 else null end) as AvgVotePerAnswer,
        a.AnswerRankForQuestion
    from AnswerStats a
    left join Votes v on v.PostId = a.Id
    group by a.Id, a.ParentId, a.OwnerUserId, a.Score, a.AnswerRankForQuestion
),
QuestionAnswerAggregate as (
    select
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        q.AcceptedAnswerId,
        max(case when tu.AnswerRankForQuestion = 1 then tu.AnswerScore end) as TopAnswerScore,
        max(case when tu.AnswerRankForQuestion = 1 then tu.UpVotes end) as TopAnswerUpVotes,
        max(case when tu.AnswerRankForQuestion = 1 then tu.DownVotes end) as TopAnswerDownVotes,
        count(distinct a.Id) as TotalAnswersCount
    from QuestionStats q
    left join TopAnswersWithVotes tu on tu.QuestionId = q.Id
    left join AnswerStats a on a.ParentId = q.Id
    group by q.Id, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Tags, q.AcceptedAnswerId
),
AnswersWithComments as (
    select
        a.Id as AnswerId,
        count(c.Id) as CommentCount,
        bool_or(case when c.UserId is null then true else false end) as HasAnonymousComment
    from Posts a
    left join Comments c on c.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id
),
ComplexPostAnalysis as (
    select
        q.QuestionId,
        q.QuestionOwner,
        q.QuestionCreation,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        coalesce(pbs.GoldBadges,0) as QuestionOwnerGoldBadges,
        coalesce(pbs.SilverBadges,0) as QuestionOwnerSilverBadges,
        coalesce(pbs.BronzeBadges,0) as QuestionOwnerBronzeBadges,
        q.TopAnswerScore,
        q.TopAnswerUpVotes,
        q.TopAnswerDownVotes,
        coalesce(ca.CommentCount, 0) as TopAnswerCommentCount,
        coalesce(ca.HasAnonymousComment, false) as TopAnswerHasAnonComment,
        case
            when q.TopAnswerScore is null then 'No answers'
            when q.TopAnswerScore > q.QuestionScore then 'Top answer outranks question'
            else 'Question ranking top'
        end as AnswerVsQuestionScoreComparison,
        (
          select string_agg(tn, ',') from (
            select distinct substr(t.TagName, 1, 10) as tn
            from Tags t
            where t.TagName = any(string_to_array(replace(replace(q.Tags,'<',''),'>',''),' '))
            order by tn
          ) s
        ) as SampleTags,
        length(trim(coalesce(q.Tags,''))) as TagsLength,
        (select count(*) from PostHistory ph where ph.PostId = q.QuestionId and ph.PostHistoryTypeId in (10, 12, 14)) as CriticalHistoryEvents,
        row_number() over (partition by q.QuestionOwner order by q.QuestionCreation desc) as RecentQuestionRank
    from QuestionAnswerAggregate q
    left join UserBadgeSummary pbs on pbs.UserId = q.QuestionOwner
    left join AnswersWithComments ca on ca.AnswerId = q.AcceptedAnswerId
    left join Tags t on t.TagName = any(string_to_array(replace(replace(q.Tags,'<',''),'>',''),' '))
    group by q.QuestionId, q.QuestionOwner, q.QuestionCreation, q.QuestionScore, q.ViewCount, q.AnswerCount, q.FavoriteCount, pbs.GoldBadges, pbs.SilverBadges, pbs.BronzeBadges, q.TopAnswerScore, q.TopAnswerUpVotes, q.TopAnswerDownVotes, ca.CommentCount, ca.HasAnonymousComment, q.Tags, q.AcceptedAnswerId
),
TopUsersRanked as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        rank() over (order by u.Reputation desc, ub.GoldBadges desc, ub.SilverBadges desc) as ReputationRank
    from Users u
    left join UserBadgeSummary ub on ub.UserId = u.Id
    where u.Reputation > 10000
),
UsersAndTheirFirstAnswers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        a.Id as FirstAnswerId,
        a.CreationDate as FirstAnswerCreation
    from Users u
    inner join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    where a.CreationDate = (
        select min(a2.CreationDate) from Posts a2 where a2.OwnerUserId = u.Id and a2.PostTypeId = 2
    )
),
FinalSet as (
    select
        cpa.QuestionId,
        cpa.QuestionOwner,
        cpa.QuestionScore,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.FavoriteCount,
        cpa.QuestionOwnerGoldBadges,
        cpa.QuestionOwnerSilverBadges,
        cpa.QuestionOwnerBronzeBadges,
        cpa.TopAnswerScore,
        cpa.TopAnswerUpVotes,
        cpa.TopAnswerDownVotes,
        cpa.TopAnswerCommentCount,
        cpa.TopAnswerHasAnonComment,
        cpa.AnswerVsQuestionScoreComparison,
        cpa.SampleTags,
        cpa.TagsLength,
        cpa.CriticalHistoryEvents,
        tur.ReputationRank,
        usfa.FirstAnswerId,
        usfa.FirstAnswerCreation,
        case when tur.ReputationRank <= 10 then 'Top10User' else 'OtherUser' end as UserCategory,
        coalesce((select count(*) from PostLinks pl where pl.PostId = cpa.QuestionId and pl.LinkTypeId = 1), 0) as OutboundLinksCount,
        coalesce((select count(*) from PostLinks pl2 where pl2.RelatedPostId = cpa.QuestionId and pl2.LinkTypeId = 3), 0) as DuplicateLinksCount
    from ComplexPostAnalysis cpa
    left join TopUsersRanked tur on tur.Id = cpa.QuestionOwner
    left join UsersAndTheirFirstAnswers usfa on usfa.UserId = cpa.QuestionOwner
    where cpa.AnswerCount > 0 and cpa.CriticalHistoryEvents > 1
)
select
    QuestionId,
    QuestionOwner,
    QuestionScore,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    QuestionOwnerGoldBadges,
    QuestionOwnerSilverBadges,
    QuestionOwnerBronzeBadges,
    TopAnswerScore,
    TopAnswerUpVotes,
    TopAnswerDownVotes,
    TopAnswerCommentCount,
    TopAnswerHasAnonComment,
    AnswerVsQuestionScoreComparison,
    SampleTags,
    TagsLength,
    CriticalHistoryEvents,
    ReputationRank,
    FirstAnswerId,
    FirstAnswerCreation,
    UserCategory,
    OutboundLinksCount,
    DuplicateLinksCount,
    coalesce(QuestionScore * 0.6 + TopAnswerScore * 0.4, 0) as WeightedScore,
    coalesce(ViewCount / nullif((extract(epoch from (timestamp '2024-10-01 12:34:56' - FirstAnswerCreation))/3600),0), 0) as ViewsPerHourSinceFirstAnswer
from FinalSet
order by WeightedScore desc, ViewCount desc
limit 100;