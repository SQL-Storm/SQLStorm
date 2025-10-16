-- {"query": "602.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1635} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(b.BadgeCount, 0) as BadgeCount,
        row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn
    from Users u
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    where u.Reputation > 1000 and u.Location is not null
),
UserQuestionStats as (
    select 
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxQuestionViews,
        sum(p.FavoriteCount) filter (where p.PostTypeId = 1) as TotalFavorites
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopTagsByUser as (
    select 
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.OwnerUserId is not null and p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, Tag
),
RankedTags as (
    select 
        UserId,
        Tag,
        TagCount,
        rank() over (partition by UserId order by TagCount desc) as TagRank
    from TopTagsByUser
),
UserTopTag as (
    select 
        UserId,
        Tag as TopTag,
        TagCount
    from RankedTags
    where TagRank = 1
),
RecentPostEdits as (
    select 
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
LatestPostEditPerPost as (
    select 
        rpe.PostId,
        rpe.UserId as EditorUserId,
        rpe.CreationDate as LastEditDate,
        rpe.PostHistoryTypeId
    from RecentPostEdits rpe
    where rpe.rn = 1
),
UserClosedQuestions as (
    select 
        p.OwnerUserId as UserId,
        count(*) as ClosedQuestionCount,
        count(distinct ph.Comment) filter (where ph.Comment in ('101','102','103','104','105')) as DistinctCloseReasons
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserVoteStats as (
    select 
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesGiven
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
UserAggregated as (
    select 
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.Location,
        rua.Views,
        rua.UpVotes,
        rua.DownVotes,
        rua.BadgeCount,
        uqs.QuestionCount,
        uqs.AnswerCount,
        coalesce(uqs.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(uqs.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(uqs.MaxQuestionViews,0) as MaxQuestionViews,
        coalesce(uqs.TotalFavorites,0) as TotalFavorites,
        utt.TopTag,
        utt.TagCount as TopTagCount,
        ucs.ClosedQuestionCount,
        coalesce(ucs.DistinctCloseReasons,0) as DistinctCloseReasons,
        coalesce(uvs.UpVotesCast,0) as UpVotesCast,
        coalesce(uvs.DownVotesCast,0) as DownVotesCast,
        coalesce(uvs.FavoritesGiven,0) as FavoritesGiven
    from RecursiveUserActivity rua
    left join UserQuestionStats uqs on rua.UserId = uqs.UserId
    left join UserTopTag utt on rua.UserId = utt.UserId
    left join UserClosedQuestions ucs on rua.UserId = ucs.UserId
    left join UserVoteStats uvs on rua.UserId = uvs.UserId
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.Views,
    ua.UpVotes,
    ua.DownVotes,
    ua.BadgeCount,
    ua.QuestionCount,
    ua.AnswerCount,
    round(ua.AvgQuestionScore,2) as AvgQuestionScore,
    round(ua.AvgAnswerScore,2) as AvgAnswerScore,
    ua.MaxQuestionViews,
    ua.TotalFavorites,
    ua.TopTag,
    ua.TopTagCount,
    ua.ClosedQuestionCount,
    ua.DistinctCloseReasons,
    ua.UpVotesCast,
    ua.DownVotesCast,
    ua.FavoritesGiven,
    case 
        when ua.Reputation > 10000 and ua.BadgeCount > 10 then 'Expert'
        when ua.Reputation between 5000 and 10000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    concat_ws(' | ', ua.TopTag, 'Questions:', ua.QuestionCount::text, 'Answers:', ua.AnswerCount::text) as Summary,
    row_number() over (order by ua.Reputation desc, ua.BadgeCount desc) as RankByReputation
from UserAggregated ua
where ua.QuestionCount > 5 or ua.AnswerCount > 10
order by RankByReputation
limit 50

union

select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    0 as BadgeCount,
    0 as QuestionCount,
    0 as AnswerCount,
    0.0 as AvgQuestionScore,
    0.0 as AvgAnswerScore,
    0 as MaxQuestionViews,
    0 as TotalFavorites,
    null as TopTag,
    0 as TopTagCount,
    0 as ClosedQuestionCount,
    0 as DistinctCloseReasons,
    0 as UpVotesCast,
    0 as DownVotesCast,
    0 as FavoritesGiven,
    'Newbie' as UserLevel,
    'No activity' as Summary,
    row_number() over (order by u.Id) + 1000 as RankByReputation
from Users u
where u.Reputation < 10
order by RankByReputation
limit 10;