-- {"query": "496.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1669} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreationDate,
        count(a.Id) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score > 5 then 1 else 0 end) as HighScoreAnswers,
        max(a.CreationDate) as LastAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate
),
TopVoters as (
    select
        v.UserId,
        count(v.Id) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    inner join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade,
        row_number() over (order by u.Reputation desc) as RankByReputation,
        lag(u.LastAccessDate) over (order by u.Id) as PrevUserLastAccess,
        lead(u.LastAccessDate) over (order by u.Id) as NextUserLastAccess
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    inner join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
AnswerersWithBadgeStats as (
    select
        a.OwnerUserId,
        count(a.Id) as AnswerCount,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges
    from Posts a
    left join UserBadgeStats ubs on ubs.UserId = a.OwnerUserId
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges
),
ComplexUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(tv.UpVotes, 0) as UpVotes,
        coalesce(tv.DownVotes, 0) as DownVotes,
        coalesce(abs.AnswerCount, 0) as AnswerCount,
        coalesce(abs.GoldBadges, 0) as GoldBadges,
        coalesce(abs.SilverBadges, 0) as SilverBadges,
        coalesce(abs.BronzeBadges, 0) as BronzeBadges,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.RankByReputation,
        ua.PrevUserLastAccess,
        ua.NextUserLastAccess
    from Users u
    left join TopVoters tv on tv.UserId = u.Id
    left join AnswerersWithBadgeStats abs on abs.OwnerUserId = u.Id
    inner join UserActivityWindow ua on ua.Id = u.Id
)
select 
    q.QuestionId,
    q.Title as QuestionTitle,
    q.TotalAnswers,
    q.AvgAnswerScore,
    q.MaxAnswerScore,
    q.HighScoreAnswers,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.UpVotes,
    u.DownVotes,
    coalesce(cq.CloseReason, 'Open') as CloseReason,
    dq.RelatedPostTitle as DuplicateOf,
    rt.TagName,
    rt.Count as TagUsageCount,
    rt.AnswerCount as TagAnswerCount,
    rt.ViewCount as TagViewCount,
    rt.Score as TagScore,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.RankByReputation,
    ua.PrevUserLastAccess,
    ua.NextUserLastAccess
from PostAnswerStats q
inner join ComplexUserStats u on u.Id = q.OwnerUserId
left join ClosedQuestionsWithReasons cq on cq.PostId = q.QuestionId and cq.rn = 1
left join DuplicateLinks dq on dq.PostId = q.QuestionId
left join RecursiveTagCounts rt on rt.rn = 1 and rt.TagName is not null and q.Title ilike '%' || rt.TagName || '%'
inner join UserActivityWindow ua on ua.Id = u.Id
where q.TotalAnswers > 5
  and (cq.CloseReason is null or cq.CloseReason not in ('Duplicate', 'Off-topic'))
  and u.Reputation > 1000
order by q.MaxAnswerScore desc, u.Reputation desc
limit 100;