-- {"query": "1285.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1527} 
with RecursivePosts as (
    select p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score,
           p.OwnerUserId, p.AcceptedAnswerId, 1 as Depth,
           array[p.Id] as PathIds
    from Posts p
    where p.PostTypeId = 1 -- Questions only
      and p.CreationDate between '2023-01-01' and '2023-12-31'
      and p.Score > 0
    union all
    select c.Id, c.PostTypeId, c.Title, c.CreationDate, c.Score,
           c.OwnerUserId, c.AcceptedAnswerId,
           rp.Depth + 1,
           rp.PathIds || c.Id
    from Posts c
    join RecursivePosts rp on c.ParentId = rp.Id
    where c.Score > 0 and rp.Depth < 3
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        coalesce(sum(b.TagBased::int), 0) as TagBasedBadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostVotesAgg as (
    select
        v.PostId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotes,
        count(*) filter (where vt.Name = 'DownMod') as DownVotes,
        count(*) filter (where vt.Name = 'Favorite') as Favorites,
        coalesce(sum(v.BountyAmount), 0) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionClosureStats as (
    select
        p.Id as QuestionId,
        ph.PostHistoryTypeId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as TimesClosed,
        count(*) filter (where ph.PostHistoryTypeId = 11) as TimesReopened,
        max(ph.CreationDate) as LastCloseDate,
        ph.Comment as CloseReasonId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (10,11)
    where p.PostTypeId = 1
    group by p.Id, ph.PostHistoryTypeId, ph.Comment
),
RankedAnswers AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScore
    from Posts a
    where a.PostTypeId = 2 -- Answers only
),
TopAnswerWithOwner as (
    select
        r.QuestionId,
        r.AnswerId,
        r.Score,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.Views as UserViews
    from RankedAnswers r
    left join Users u on u.Id = r.OwnerUserId
    where r.RankByScore = 1
),
FinalCTE as (
    select
        rp.Id as QuestionId,
        rp.Title,
        rp.Score as QuestionScore,
        rp.CreationDate as QuestionPosted,
        pvc.UpVotes,
        pvc.DownVotes,
        pvc.Favorites,
        pvc.TotalBounty,
        pld.DuplicateCount,
        pld.LinkedCount,
        qcs.TimesClosed,
        qcs.TimesReopened,
        qcs.LastCloseDate,
        qcs.CloseReasonId,
        tub.GoldBadges,
        tub.SilverBadges,
        tub.BronzeBadges,
        tub.TagBasedBadgeCount,
        ta.AnswerId as TopAnswerId,
        ta.Score as TopAnswerScore,
        ta.OwnerUserId as TopAnswerOwnerId,
        ta.DisplayName as TopAnswerOwnerName,
        ta.Reputation as TopAnswerOwnerRep,
        ta.Location as TopAnswerOwnerLocation,
        row_number() over (partition by rp.Id order by rp.Score desc) as QuestionRankByScore,
        coalesce(ulp.LastLoginDate, to_timestamp(0)) as LastUserLogin
    from RecursivePosts rp
    left join PostVotesAgg pvc on pvc.PostId = rp.Id
    left join PostLinkDuplicates pld on pld.PostId = rp.Id
    left join QuestionClosureStats qcs on qcs.QuestionId = rp.Id
    left join UserBadgeCounts tub on tub.UserId = rp.OwnerUserId
    left join TopAnswerWithOwner ta on ta.QuestionId = rp.Id
    left join lateral (
        select max(u.LastAccessDate) as LastLoginDate from Users u where u.Id = rp.OwnerUserId
    ) ulp on true
    where rp.Depth = 1
)
select
    QuestionId,
    Title,
    QuestionPosted,
    QuestionScore,
    UpVotes,
    DownVotes,
    Favorites,
    TotalBounty,
    DuplicateCount,
    LinkedCount,
    TimesClosed,
    TimesReopened,
    LastCloseDate,
    case 
      when CloseReasonId::int in (101,1) then 'Duplicate'
      when CloseReasonId::int in (102,2) then 'Off-topic'
      when CloseReasonId::int in (103) then 'Needs details or clarity'
      when CloseReasonId::int in (104) then 'Needs more focus'
      when CloseReasonId::int in (105) then 'Opinion-based'
      else 'Other/None'
    end as CloseReason,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagBasedBadgeCount,
    TopAnswerId,
    TopAnswerScore,
    TopAnswerOwnerId,
    TopAnswerOwnerName,
    TopAnswerOwnerRep,
    TopAnswerOwnerLocation,
    QuestionRankByScore,
    LastUserLogin,
    length(Title) as TitleLength,
    (case when Favorites is null then 0 else Favorites end)::float / nullif(QuestionScore,0) as FavoriteToScoreRatio,
    (select count(1) from Comments c where c.PostId = FinalCTE.QuestionId and strpos(lower(c.Text), 'sql') > 0) as SqlCommentCount
from FinalCTE
where QuestionRankByScore <= 10
order by QuestionScore desc, Favorites desc
limit 50;