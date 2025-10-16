-- {"query": "110.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1536} 
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
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreDenseRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate
    having count(c.Id) > 5
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.Id as AcceptedAnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAccept
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as ScoreLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.CreationDate > current_date - interval '1 year'
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
UserReputationBuckets as (
    select
        Id,
        DisplayName,
        Reputation,
        case
            when Reputation >= 100000 then 'Legendary'
            when Reputation >= 10000 then 'Expert'
            when Reputation >= 1000 then 'Intermediate'
            when Reputation >= 100 then 'Novice'
            else 'Newbie'
        end as ReputationLevel
    from Users
)
select
    u.DisplayName,
    u.Reputation,
    ubs.ReputationLevel,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    ua.PostsLast30Days,
    ua.ScoreLast30Days,
    coalesce(ac.AnswerScore, 0) as AcceptedAnswerScore,
    coalesce(ac.HoursToAccept, null) as HoursToAcceptAcceptedAnswer,
    coalesce(d.DuplicateCount, 0) as DuplicateLinksCount,
    coalesce(crc.CloseVotesCount, 0) as CloseVotesCount,
    string_agg(distinct rth.TagName, ', ') as SampleTags,
    max(ps.Score) as MaxPostScore,
    min(ps.Score) as MinPostScore,
    avg(ps.Score) as AvgPostScore
from Users u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join UserActivityWindow ua on ua.UserId = u.Id
left join AcceptedAnswerStats ac on ac.AnswerOwner = u.Id
left join (
    select
        pl.PostId,
        count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
) d on d.PostId = ua.PostId
left join CloseReasonsCount crc on crc.PostId = ua.PostId
left join RecursiveTagHierarchy rth on rth.Level = 1
left join PostScoreRanks ps on ps.OwnerUserId = u.Id
where u.Reputation > 5000
group by u.Id, u.DisplayName, u.Reputation, ubs.ReputationLevel, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBasedBadges, ua.PostsLast30Days, ua.ScoreLast30Days, ac.AnswerScore, ac.HoursToAccept, d.DuplicateCount, crc.CloseVotesCount
order by u.Reputation desc, MaxPostScore desc
limit 100;