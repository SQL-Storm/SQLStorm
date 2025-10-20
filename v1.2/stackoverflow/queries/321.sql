with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
TopPostsPerTag as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AvgAnswerScore
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    where u.Reputation > 1000
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
PostVoteSummary as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(pc.CloseReason, 'Open') as CloseReason,
        coalesce(pvs.UpVotes, 0) as QuestionUpVotes,
        coalesce(pvs.DownVotes, 0) as QuestionDownVotes,
        coalesce(pvs.TotalBounty, 0) as QuestionBounty,
        count(a.AnswerId) as TotalAnswers,
        max(case when a.AnswerRank = 1 then a.Score else null end) as TopAnswerScore,
        min(case when a.AnswerRank = 1 then a.AnswerId else null end) as TopAnswerId
    from Posts q
    left join PostCloseReasons pc on pc.PostId = q.Id
    left join PostVoteSummary pvs on pvs.PostId = q.Id
    left join AnswerRanks a on a.QuestionId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, pc.CloseReason, pvs.UpVotes, pvs.DownVotes, pvs.TotalBounty
),
UserAnswerDetails as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerCount,
        max(a.Score) as MaxAnswerScore,
        min(a.CreationDate) as FirstAnswerDate,
        max(a.CreationDate) as LastAnswerDate
    from Users u
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Posts q on q.Id = a.ParentId
    group by u.Id, u.DisplayName
),
ComplexStringAnalysis as (
    select
        p.Id as PostId,
        p.Title,
        length(p.Body) as BodyLength,
        length(regexp_replace(p.Body, '[^a-zA-Z]', '', 'g')) as AlphaChars,
        length(regexp_replace(p.Body, '[^0-9]', '', 'g')) as NumericChars,
        case
            when p.Tags is null then 0
            else array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1)
        end as TagCount,
        coalesce(pc.CloseReason, 'Open') as CloseReason
    from Posts p
    left join PostCloseReasons pc on pc.PostId = p.Id
    where p.PostTypeId = 1
),
FinalSelection as (
    select
        qas.QuestionId,
        qas.Title,
        qas.CreationDate as QuestionCreation,
        qas.QuestionScore,
        qas.ViewCount,
        qas.CloseReason,
        qas.QuestionUpVotes,
        qas.QuestionDownVotes,
        qas.QuestionBounty,
        qas.TotalAnswers,
        qas.TopAnswerScore,
        uad.UserId as TopAnswerUserId,
        uad.DisplayName as TopAnswerUserName,
        uad.AnswerCount as TopAnswerUserAnswerCount,
        uad.AvgAnswerScore as TopAnswerUserAvgScore,
        uad.AcceptedAnswerCount as TopAnswerUserAcceptedCount,
        csa.BodyLength,
        csa.AlphaChars,
        csa.NumericChars,
        csa.TagCount,
        utc.TagName,
        utc.Count as TagGlobalCount,
        utc.Score as TagTopPostScore
    from QuestionAnswerStats qas
    left join Posts ta on ta.Id = qas.TopAnswerId
    left join UserAnswerDetails uad on uad.UserId = ta.OwnerUserId
    left join ComplexStringAnalysis csa on csa.PostId = qas.QuestionId
    left join TopPostsPerTag utc on utc.PostId = qas.QuestionId
    where qas.QuestionScore > 10 and qas.TotalAnswers > 2
)
select distinct
    FinalSelection.QuestionId,
    FinalSelection.Title,
    FinalSelection.QuestionCreation,
    FinalSelection.QuestionScore,
    FinalSelection.ViewCount,
    FinalSelection.CloseReason,
    FinalSelection.QuestionUpVotes,
    FinalSelection.QuestionDownVotes,
    FinalSelection.QuestionBounty,
    FinalSelection.TotalAnswers,
    FinalSelection.TopAnswerScore,
    FinalSelection.TopAnswerUserId,
    FinalSelection.TopAnswerUserName,
    FinalSelection.TopAnswerUserAnswerCount,
    FinalSelection.TopAnswerUserAvgScore,
    FinalSelection.TopAnswerUserAcceptedCount,
    FinalSelection.BodyLength,
    FinalSelection.AlphaChars,
    FinalSelection.NumericChars,
    FinalSelection.TagCount,
    FinalSelection.TagName,
    FinalSelection.TagGlobalCount,
    FinalSelection.TagTopPostScore
from FinalSelection
order by FinalSelection.QuestionScore desc, FinalSelection.ViewCount desc, FinalSelection.TotalAnswers desc
limit 100;