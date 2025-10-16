-- {"query": "399.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1396} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, 1 as Level
    from Tags t
    where t.Count > 1000
    union all
    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, t2.IsModeratorOnly, t2.IsRequired, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id - 1 and r.Level < 3
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        row_number() over (partition by u.Id order by b.Date desc) as RecentBadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
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
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as PostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2) and p.CreationDate > current_date - interval '365 days'
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
        (select count(*) from DuplicateLinks dl where dl.PostId = p.Id) as DuplicateCount,
        (select count(*) from DuplicateLinks dl where dl.RelatedPostId = p.Id) as DuplicatedByCount
    from Posts p
    where p.PostTypeId = 1
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(v.VoteTypeId = 2), 0) as TotalUpVotes,
        coalesce(sum(v.VoteTypeId = 3), 0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseDate,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    group by u.Id, u.DisplayName
)
select
    uas.UserId,
    uas.DisplayName,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    coalesce(uas.LastPostDate, '1970-01-01') as LastPostDate,
    uas.LastCloseDate,
    uas.LastReopenDate,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    ptw.PostRank,
    ptw.Score as CurrentPostScore,
    ptw.PrevScore,
    ptw.NextScore,
    qwd.DuplicateCount,
    qwd.DuplicatedByCount,
    rth.Level as TagHierarchyLevel,
    rth.TagName,
    case
        when ptw.Tags is null then 'No Tags'
        when position('sql' in lower(ptw.Tags)) > 0 then 'Contains SQL'
        else 'Other Tags'
    end as TagCategory,
    length(coalesce(ptw.Tags, '')) as TagLength,
    length(coalesce(uas.DisplayName, '')) as DisplayNameLength,
    coalesce(uas.TotalUpVotes,0) - coalesce(uas.TotalDownVotes,0) as NetVotes,
    case
        when uas.TotalUpVotes + uas.TotalDownVotes = 0 then null
        else round(cast(uas.TotalUpVotes as numeric) / (uas.TotalUpVotes + uas.TotalDownVotes), 3)
    end as UpVoteRatio
from UserActivitySummary uas
left join UserBadgeStats ubs on ubs.UserId = uas.UserId and ubs.RecentBadgeRank = 1
left join PostActivityWindow ptw on ptw.OwnerUserId = uas.UserId and ptw.PostRank = 1
left join QuestionsWithDuplicates qwd on qwd.Id = ptw.Id
left join RecursiveTagHierarchy rth on rth.TagName = (select unnest(string_to_array(substring(ptw.Tags from 2 for char_length(ptw.Tags)-2), '><')) limit 1)
where uas.QuestionsAsked > 5
  and (uas.TotalUpVotes > 100 or uas.TotalDownVotes > 50)
order by uas.TotalUpVotes desc, uas.QuestionsAsked desc
limit 100;