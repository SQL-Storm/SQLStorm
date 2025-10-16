-- {"query": "432.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1506} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        coalesce(sum(v.VoteTypeId = 2::int)::int, 0) as TotalUpVotes,
        coalesce(sum(v.VoteTypeId = 3::int)::int, 0) as TotalDownVotes,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as LastEditRank,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), UserBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
), UserPostScores as (
    select
        p.OwnerUserId as UserId,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        stddev_samp(p.Score) as StdDevPostScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), UserCloseVoteActivity as (
    select
        ph.UserId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCast,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotesCast,
        count(*) filter (where ph.PostHistoryTypeId in (10,11)) as TotalCloseReopenVotes
    from PostHistory ph
    where ph.UserId is not null
    group by ph.UserId
), UserLastActivity as (
    select
        u.Id as UserId,
        greatest(
            coalesce(max(p.LastActivityDate), '1900-01-01'::timestamp),
            coalesce(max(c.CreationDate), '1900-01-01'::timestamp),
            coalesce(max(ph.CreationDate), '1900-01-01'::timestamp)
        ) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
), UserTagEngagement as (
    select
        u.Id as UserId,
        tag,
        count(*) as PostsWithTag
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as tag
    group by u.Id, tag
), TopUserTags as (
    select distinct on (UserId)
        UserId,
        tag as TopTag,
        PostsWithTag
    from UserTagEngagement
    order by UserId, PostsWithTag desc
), UserDuplicateLinkStats as (
    select
        p.OwnerUserId as UserId,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount,
        count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedPostsCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.OwnerUserId is not null
    group by p.OwnerUserId
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.CommentsCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    coalesce(ubs.TotalBadges, 0) as TotalBadges,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    ubs.HasTagBasedBadge,
    ups.AvgPostScore,
    ups.MaxPostScore,
    ups.MinPostScore,
    ups.StdDevPostScore,
    ucv.CloseVotesCast,
    ucv.ReopenVotesCast,
    ucv.TotalCloseReopenVotes,
    ula.LastActivityDate,
    tut.TopTag,
    tut.PostsWithTag,
    udls.DuplicateLinksCount,
    udls.LinkedPostsCount,
    case
        when ua.Reputation > 10000 then 'Expert'
        when ua.Reputation between 1000 and 10000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    case
        when ua.QuestionsCount = 0 then null
        else round(ua.AnswersCount::numeric / ua.QuestionsCount, 2)
    end as AnswerToQuestionRatio,
    case
        when ua.TotalUpVotes + ua.TotalDownVotes = 0 then null
        else round(ua.TotalUpVotes::numeric / (ua.TotalUpVotes + ua.TotalDownVotes), 4)
    end as UpVoteRatio,
    concat(
        'User ', ua.DisplayName,
        ' has ', ua.QuestionsCount, ' questions and ',
        ua.AnswersCount, ' answers. ',
        coalesce(tut.TopTag, 'No Tags'), ' is their top tag with ',
        coalesce(tut.PostsWithTag::text, '0'), ' posts.'
    ) as Summary
from RecursiveUserActivity ua
left join UserBadgeStats ubs on ubs.UserId = ua.UserId
left join UserPostScores ups on ups.UserId = ua.UserId
left join UserCloseVoteActivity ucv on ucv.UserId = ua.UserId
left join UserLastActivity ula on ula.UserId = ua.UserId
left join TopUserTags tut on tut.UserId = ua.UserId
left join UserDuplicateLinkStats udls on udls.UserId = ua.UserId
where ua.Reputation > 2000
order by ua.Reputation desc, ua.QuestionsCount desc
limit 100;