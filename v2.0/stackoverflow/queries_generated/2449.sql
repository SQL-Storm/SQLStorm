-- {"query": "2449.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1512} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        case when p.PostTypeId = 1 then array_to_string(
            regexp_matches(
                substring(p.Tags from 2 for length(p.Tags) - 2),
                '[^><]+', 'g'), ',') else null end as TagList,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from users u
    left join posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserTopTags as (
    select
        rup.UserId,
        tag,
        count(1) as TagCount
    from RecursiveUserPosts rup,
    unnest(string_to_array(coalesce(rup.TagList, ''), ',')) as tag
    where tag <> ''
    group by rup.UserId, tag
    having count(1) > 1
),
UserBadgesSummary as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct case when b.TagBased = 1 then b.Name end) as TagBasedBadgeCount
    from badges b
    group by b.UserId
),
PostActivityWindows as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        count(distinct c.Id) over (partition by p.Id order by c.CreationDate rows between unbounded preceding and current row) as CumulativeCommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by p.Id order by v.CreationDate rows between unbounded preceding and current row) as CumulativeUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by p.Id order by v.CreationDate rows between unbounded preceding and current row) as CumulativeDownVotes
    from posts p
    left join comments c on c.PostId = p.Id
    left join votes v on v.PostId = p.Id
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from posthistory ph
    join closereasontypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
DuplicatesAndLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkType,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from postlinks pl
    join linktypes lt on lt.Id = pl.LinkTypeId
    left join posts p1 on p1.Id = pl.PostId
    left join posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),
UserEngagementAggregate as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as Questions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as Answers,
        count(distinct c.Id) as Comments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        max(p.Score) as HighestPostScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.CreationDate) as LastPostDate,
        extract(epoch from max(p.CreationDate) - min(p.CreationDate))/86400 as DaysActive
    from users u
    left join posts p on p.OwnerUserId = u.Id
    left join comments c on c.UserId = u.Id
    left join votes v on v.UserId = u.Id
    group by u.Id
),
TopDuplicateQuestions as (
    select distinct p1.Id, p1.Title, p1.Score, d.RelatedPostId as DuplicateOf
    from posts p1
    join duplicatesandlinks d on d.PostId = p1.Id and d.LinkType = 'Duplicate'
    where p1.PostTypeId = 1 and p1.Score > 100
),
RecursiveUserBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        b.TagBased,
        row_number() over (partition by b.UserId order by b.Date desc) as Rank
    from badges b
    where b.Class in (1, 2) and b.TagBased = 0
)
select
    u.Id as UserId,
    u.DisplayName,
    coalesce(uba.GoldBadges,0) as GoldBadges,
    coalesce(uba.SilverBadges,0) as SilverBadges,
    coalesce(uba.BronzeBadges,0) as BronzeBadges,
    coalesce(uba.TagBasedBadgeCount,0) as TagBasedBadges,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ua.HighestPostScore,
    ua.DaysActive,
    tdt.Title as HighScoreDuplicateQuestion,
    tdt.DuplicateOf,
    array_to_string(array_agg(distinct ut.tag order by ut.TagCount desc limit 3), ', ') as TopTags,
    string_agg(distinct concat(rb.Name, '(', rb.Class, ')'), ', ' order by rb.Rank) as RecentNamedBadges
from users u
left join UserBadgesSummary uba on uba.UserId = u.Id
left join UserEngagementAggregate ua on ua.UserId = u.Id
left join TopDuplicateQuestions tdt on tdt.Id in (
    select PostId from posts p where p.OwnerUserId = u.Id order by Score desc limit 1
)
left join UserTopTags ut on ut.UserId = u.Id
left join RecursiveUserBadges rb on rb.UserId = u.Id and rb.Rank <= 5
where u.Reputation > 1000
group by u.Id, u.DisplayName, uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges, uba.TagBasedBadgeCount, ua.Questions, ua.Answers, ua.Comments, ua.UpVotesReceived, ua.DownVotesReceived, ua.HighestPostScore, ua.DaysActive, tdt.Title, tdt.DuplicateOf
order by ua.UpVotesReceived desc nulls last, ua.HighestPostScore desc nulls last
limit 50;