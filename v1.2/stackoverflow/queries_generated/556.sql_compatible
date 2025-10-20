with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as UserId,
        u.Reputation,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where (case when t.IsModeratorOnly then 1 else 0 end) = 0 and (case when t.IsRequired then 1 else 0 end) = 0
),
TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 10
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as UniqueBadgeNames
    from Badges b
    group by b.UserId
),
PostVoteStats as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
AcceptedAnswerInfo as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by cht.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionsCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswersCount,
        count(c.Id) as CommentsCount,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        row_number() over (order by u.Reputation desc) as RankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
HighImpactUsers as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.CommentsCount,
        ua.TotalPostScore,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.UniqueBadgeNames,0) as UniqueBadgeNames
    from UserActivityWindow ua
    left join UserBadgeStats ubs on ubs.UserId = ua.UserId
    where ua.Reputation > 10000 and ua.QuestionsCount + ua.AnswersCount > 50
),
PostLinkSummary as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore,
        case when p2.PostTypeId = 1 then 'Question' else 'Other' end as RelatedPostType,
        row_number() over (partition by pl.PostId order by pl.CreationDate desc) as LinkRank
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
TopPostLinks as (
    select * from PostLinkSummary where LinkRank <= 5
),
QuestionAnswerRatios as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as Questions,
        count(case when p.PostTypeId = 2 then 1 end) as Answers,
        case when count(case when p.PostTypeId = 1 then 1 end) = 0 then null
             else 1.0 * count(case when p.PostTypeId = 2 then 1 end) / count(case when p.PostTypeId = 1 then 1 end) end as AnswerQuestionRatio
    from Posts p
    group by p.OwnerUserId
),
FinalResult as (
    select
        ttp.TagName,
        ttp.PostId,
        ttp.Score as PostScore,
        ttp.ViewCount,
        ttp.CreationDate as PostCreationDate,
        coalesce(u.DisplayName, 'Unknown') as OwnerName,
        coalesce(u.Reputation, 0) as OwnerReputation,
        coalesce(uvs.UpVotes, 0) as UpVotes,
        coalesce(uvs.DownVotes, 0) as DownVotes,
        coalesce(uvs.TotalBounty, 0) as TotalBounty,
        coalesce(aai.AnswerScore, 0) as AcceptedAnswerScore,
        coalesce(aai.AnswerOwnerName, 'None') as AcceptedAnswerOwner,
        coalesce(hui.GoldBadges, 0) as OwnerGoldBadges,
        coalesce(hui.SilverBadges, 0) as OwnerSilverBadges,
        coalesce(hui.BronzeBadges, 0) as OwnerBronzeBadges,
        coalesce(qar.AnswerQuestionRatio, 0) as AnswerQuestionRatio,
        case when ttp.Score > 0 and ttp.ViewCount > 1000 then 'High Impact'
             when ttp.Score <= 0 then 'Low Impact'
             else 'Moderate Impact' end as ImpactCategory
    from TopTagPosts ttp
    left join Users u on u.Id = ttp.UserId
    left join PostVoteStats uvs on uvs.PostId = ttp.PostId
    left join AcceptedAnswerInfo aai on aai.QuestionId = ttp.PostId
    left join HighImpactUsers hui on hui.UserId = ttp.UserId
    left join QuestionAnswerRatios qar on qar.OwnerUserId = ttp.UserId
)
select
    fr.TagName,
    fr.PostId,
    fr.PostScore,
    fr.ViewCount,
    fr.PostCreationDate,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.UpVotes,
    fr.DownVotes,
    fr.TotalBounty,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerOwner,
    fr.OwnerGoldBadges,
    fr.OwnerSilverBadges,
    fr.OwnerBronzeBadges,
    fr.AnswerQuestionRatio,
    fr.ImpactCategory,
    crc.CloseReason,
    crc.CloseCount
from FinalResult fr
left join CloseReasonCounts crc on crc.CloseReason = 'Duplicate'
where fr.PostCreationDate > cast('2024-10-01' as date) - interval '1 year'
order by fr.OwnerReputation desc, fr.PostScore desc
limit 100;