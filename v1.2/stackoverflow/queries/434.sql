-- {"query": "434.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1486} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        p.OwnerUserId,
        u.Reputation,
        u.DisplayName,
        dense_rank() over (partition by t.Id order by p.Score desc) as ScoreRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.TagName is not null
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(c.Id) over (partition by p.Id) as CommentCount,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
TopPostsWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountySum
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and crt.Name is not null
    group by ph.PostId, crt.Name
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) as QuestionCount,
        count(distinct a.Id) as AnswerCount,
        sum(coalesce(p.Score,0)) as TotalQuestionScore,
        sum(coalesce(a.Score,0)) as TotalAnswerScore,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
RecentEdits as (
    select
        ph.PostId,
        ph.UserId,
        u.DisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as EditRank
    from PostHistory ph
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId in (4,5,6)
)
select
    rtc.TagName,
    rtc.Count as TagUsageCount,
    rtc.AnswerCount,
    rtc.ViewCount,
    rtc.Score as TagExcerptScore,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    urw.DisplayName as TopUserByReputation,
    urw.Reputation as TopUserReputation,
    urw.QuestionCount,
    urw.AnswerCount,
    urw.TotalQuestionScore,
    urw.TotalAnswerScore,
    dp.UpVotes,
    dp.DownVotes,
    dp.BountySum,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.PostOwner as DuplicatePostOwner,
    dl.RelatedPostOwner as OriginalPostOwner,
    crc.CloseReason,
    crc.CloseCount,
    re.UserId as LastEditorUserId,
    re.DisplayName as LastEditorName,
    re.CreationDate as LastEditDate,
    re.Comment as LastEditComment,
    case
        when rtc.AnswerCount > 100 then 'High Activity'
        when rtc.AnswerCount between 50 and 100 then 'Medium Activity'
        else 'Low Activity'
    end as ActivityLevel,
    case
        when dp.UpVotes - dp.DownVotes > 100 then 'Highly Upvoted'
        when dp.UpVotes - dp.DownVotes between 10 and 100 then 'Moderately Upvoted'
        else 'Low Upvotes'
    end as VoteSentiment,
    concat('Tag: ', rtc.TagName, ' | Owner: ', coalesce(rtc.DisplayName, 'Unknown')) as TagOwnerInfo
from RecursiveTagCounts rtc
left join UserBadgeSummary ubs on ubs.UserId = rtc.OwnerUserId
left join UserReputationWindow urw on urw.Id = rtc.OwnerUserId
left join TopPostsWithVotes dp on dp.Id = rtc.Id
left join DuplicateLinks dl on dl.PostId = rtc.Id
left join CloseReasonCounts crc on crc.PostId = rtc.Id
left join RecentEdits re on re.PostId = rtc.Id and re.EditRank = 1
where rtc.ScoreRank = 1
order by rtc.Count desc, urw.Reputation desc
limit 100;