with recursive RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(pg.ParentId, 0) as ParentId,
        1 as Level
    from Tags t
    left join Posts pg on t.ExcerptPostId = pg.Id
    union all
    select
        rtc.Id,
        rtc.TagName,
        rtc.Count,
        coalesce(pg.ParentId, 0),
        rtc.Level + 1
    from RecursiveTagCounts rtc
    join Posts pg on rtc.ParentId = pg.Id
    where rtc.Level < 3
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        sum(case when p.PostTypeId in (1,2) then p.Score else 0 end) as TotalScore,
        avg(case when p.PostTypeId = 1 then p.ViewCount end) as AvgQuestionViews,
        max(p.CreationDate) as LastPostDate,
        count(distinct b.Id) as BadgeCount,
        max(case when b.Class = 1 then 1 else 0 end) as HasGoldBadge
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
RankedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.PostTypeId,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank,
        count(*) over (partition by p.ParentId) as TotalAnswers
    from Posts p
    where p.PostTypeId = 2
),
TopAnswersByUser as (
    select 
        ra.ParentId as QuestionId,
        ra.Id as AnswerId,
        ra.OwnerUserId,
        ra.Score,
        ra.CreationDate,
        u.DisplayName as AnswerUserDisplay,
        q.Title,
        q.Tags
    from RankedAnswers ra
    join Posts q on q.Id = ra.ParentId and q.PostTypeId = 1
    left join Users u on u.Id = ra.OwnerUserId
    where ra.AnswerRank = 1
),
DuplicateLinkCounts as (
    select 
        pl.PostId,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount,
        max(pl.CreationDate) as LastDuplicateLinkDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
CloseVoteActivity as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotes,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVotes,
        count(case when ph.PostHistoryTypeId = 12 then 1 end) as Deletions,
        max(ph.CreationDate) as LastActivity
    from PostHistory ph
    group by ph.PostId
),
UserVoteSummary as (
    select
        v.UserId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotesGiven,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotesGiven,
        count(distinct v.PostId) as PostsVotedOn,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.UserId
),
ComplexTagCalculations as (
    select 
        rtc.TagName,
        sum(rtc.Count) as TotalTagCount,
        sum(case when rtc.Level = 1 then rtc.Count else 0 end) as Level1Count,
        sum(case when rtc.Level = 2 then rtc.Count else 0 end) as Level2Count,
        sum(case when rtc.Level = 3 then rtc.Count else 0 end) as Level3Count,
        string_agg(concat(rtc.TagName, ':', cast(rtc.Level as varchar)), ',' ORDER BY rtc.Level) as TagLevelSummary
    from RecursiveTagCounts rtc
    group by rtc.TagName
)
select 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalScore,
    ups.AvgQuestionViews,
    ups.LastPostDate,
    ups.BadgeCount,
    case when ups.HasGoldBadge = 1 then 'Yes' else 'No' end as HasGoldBadge,
    vas.AnswerId as TopAnswerId,
    vas.Score as TopAnswerScore,
    vas.AnswerUserDisplay,
    vl.DuplicateCount,
    vl.LastDuplicateLinkDate,
    cv.CloseVotes,
    cv.ReopenVotes,
    cv.Deletions,
    cv.LastActivity as LastPostHistoryActivity,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.PostsVotedOn,
    uv.LastVoteDate,
    ctc.TotalTagCount,
    ctc.Level1Count,
    ctc.Level2Count,
    ctc.Level3Count,
    ctc.TagLevelSummary
from UserPostStats ups
left join TopAnswersByUser vas on vas.OwnerUserId = ups.UserId
left join DuplicateLinkCounts vl on vl.PostId = vas.AnswerId
left join CloseVoteActivity cv on cv.PostId = vas.AnswerId
left join UserVoteSummary uv on uv.UserId = ups.UserId
left join (
    select 
        p.OwnerUserId,
        ctc.TotalTagCount,
        ctc.Level1Count,
        ctc.Level2Count,
        ctc.Level3Count,
        ctc.TagLevelSummary
    from Posts p
    left join lateral (
        select
            sum(rtc.Count) as TotalTagCount,
            sum(case when rtc.Level = 1 then rtc.Count else 0 end) as Level1Count,
            sum(case when rtc.Level = 2 then rtc.Count else 0 end) as Level2Count,
            sum(case when rtc.Level = 3 then rtc.Count else 0 end) as Level3Count,
            string_agg(concat(rtc.TagName, ':', cast(rtc.Level as varchar)), ',' ORDER BY rtc.Level) as TagLevelSummary
        from RecursiveTagCounts rtc
        where exists (
            select 1 from Posts pq
            where pq.OwnerUserId = p.OwnerUserId and 
                strpos(coalesce(pq.Tags, ''), rtc.TagName) > 0
        )
    ) ctc on true
    where p.OwnerUserId is not null
    group by p.OwnerUserId, ctc.TotalTagCount, ctc.Level1Count, ctc.Level2Count, ctc.Level3Count, ctc.TagLevelSummary
) ctc on ctc.OwnerUserId = ups.UserId
where ups.Reputation > 1000
order by ups.TotalScore desc nulls last, ups.Reputation desc
limit 100;