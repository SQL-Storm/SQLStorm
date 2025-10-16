-- {"query": "578.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1463} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(v.VoteTypeId = 2)::int,0) as TotalUpVotes,
        coalesce(sum(v.VoteTypeId = 3)::int,0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate asc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AnswerDownVotes,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
BadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ') as BadgeNames
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        sum(coalesce(p.Score,0)) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePostScore,
        count(p.Id) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePostCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    left join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by cht.Name
    having count(ph.Id) > 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
UserCommentStats as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Text ilike '%sql%' then 1 else 0 end) as SqlMentions
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
)
select
    ua.DisplayName as User,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.LastPostDate,
    coalesce(bs_gold.BadgeCount,0) as GoldBadges,
    coalesce(bs_silver.BadgeCount,0) as SilverBadges,
    coalesce(bs_bronze.BadgeCount,0) as BronzeBadges,
    pr.ScoreRank as PostScoreRank,
    aa.AnswerScore,
    aa.AnswerUpVotes,
    aa.AnswerDownVotes,
    aa.AnswerCommentCount,
    crc.CloseReason,
    crc.CloseCount,
    dc.PostTitle as DuplicatePostTitle,
    dc.RelatedPostTitle as DuplicateRelatedPostTitle,
    ucs.CommentCount,
    round(ucs.AvgCommentLength,2) as AvgCommentLength,
    ucs.SqlMentions,
    urw.CumulativePostScore,
    urw.CumulativePostCount,
    rt.Level as TagHierarchyLevel,
    array_to_string(rt.Path, ' > ') as TagPath
from UserActivity ua
left join BadgeSummary bs_gold on bs_gold.UserId = ua.UserId and bs_gold.Class = 1
left join BadgeSummary bs_silver on bs_silver.UserId = ua.UserId and bs_silver.Class = 2
left join BadgeSummary bs_bronze on bs_bronze.UserId = ua.UserId and bs_bronze.Class = 3
left join PostScoreRanks pr on pr.OwnerUserId = ua.UserId and pr.ScoreRank <= 10
left join AcceptedAnswerStats aa on aa.QuestionOwner = ua.UserId
left join CloseReasonCounts crc on true
left join DuplicateLinks dc on dc.PostId = (select min(Id) from Posts where OwnerUserId = ua.UserId)
left join UserCommentStats ucs on ucs.UserId = ua.UserId
left join UserReputationWindow urw on urw.UserId = ua.UserId
left join RecursiveTagHierarchy rt on rt.Level = 1
where ua.QuestionCount > 5 or ua.AnswerCount > 10
order by ua.TotalUpVotes desc, ua.QuestionCount desc
limit 100;