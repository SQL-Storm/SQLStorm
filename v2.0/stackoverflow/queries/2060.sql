-- {"query": "2060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1663}
with RecursiveUserStats as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Views desc) as Rank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopUsersPosts as (
    select 
        r.Id as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        coalesce(p.OwnerDisplayName, r.DisplayName) as OwnerName,
        case 
            when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1
            else 0
        end as HasAcceptedAnswer,
        row_number() over (partition by r.Id order by p.CreationDate desc) as PostRank
    from RecursiveUserStats r
    left join Posts p on p.OwnerUserId = r.Id
    where r.Rank between 1 and 50
),
TagAggregates as (
    select 
        tag,
        p.OwnerUserId,
        count(*) as PostsWithTag,
        avg(p.Score) as AvgScorePerTag
    from (
        select
            p.*,
            trim(t.value) as tag
        from Posts p
        cross join lateral (
            select regexp_substr(p.Tags, '<([^>]+)>', 1, seq) as value
            from (
                select generate_series(1, greatest(length(coalesce(p.Tags,'')) - length(replace(coalesce(p.Tags,''), '<', '')),0)) as seq
            ) s
        ) t
        where p.PostTypeId = 1 and p.Tags is not null
    ) p
    where tag is not null
    group by tag, p.OwnerUserId
),
UserTagRankings as (
    select
        ta.OwnerUserId,
        ta.tag as Tag,
        ta.PostsWithTag,
        ta.AvgScorePerTag,
        rank() over (partition by ta.OwnerUserId order by ta.PostsWithTag desc, ta.AvgScorePerTag desc) as TagRank
    from TagAggregates ta
),
LatestPostHistory as (
    select *
    from (
        select
            ph.PostId,
            ph.PostHistoryTypeId,
            ph.CreationDate,
            ph.Comment,
            ph.UserId,
            ph.UserDisplayName,
            row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
        from PostHistory ph
        where ph.PostHistoryTypeId in (10, 11)
    ) t
    where rn = 1
),
CloseStats as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        lph.PostHistoryTypeId,
        count(case when lph.PostHistoryTypeId = 10 then 1 end) as CloseCount,
        count(case when lph.PostHistoryTypeId = 11 then 1 end) as ReopenCount,
        max(lph.CreationDate) as LastCloseOrReopen,
        bool_or(lph.PostHistoryTypeId = 10) as IsCurrentlyClosed
    from Posts p 
    left join LatestPostHistory lph on p.Id = lph.PostId
    group by p.Id, p.OwnerUserId, lph.PostHistoryTypeId
),
PostLinkAggregates as (
    select 
        pl.PostId,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks,
        sum(case when lt.Name = 'Linked' then 1 else 0 end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserPerformance as (
    select
        r.Id as UserId,
        r.DisplayName,
        r.Reputation,
        r.Views,
        r.UpVotes,
        r.DownVotes,
        r.BadgeCount,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        sum(case when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswer,
        sum(coalesce(pl.DuplicateLinks,0)) as TotalDuplicateLinks,
        sum(coalesce(pl.LinkedPosts,0)) as TotalLinkedPosts,
        sum(case when cs.IsCurrentlyClosed then 1 else 0 end) as CurrentlyClosedPosts
    from RecursiveUserStats r
    left join Posts p on p.OwnerUserId = r.Id
    left join PostLinkAggregates pl on p.Id = pl.PostId
    left join CloseStats cs on p.Id = cs.PostId
    where r.Rank <= 50
    group by r.Id, r.DisplayName, r.Reputation, r.Views, r.UpVotes, r.DownVotes, r.BadgeCount, r.GoldBadges, r.SilverBadges, r.BronzeBadges
),
UserRankedTags as (
    select
        utr.OwnerUserId,
        string_agg(utr.Tag || ' (' || utr.PostsWithTag || ' posts, avg score ' || cast(round(utr.AvgScorePerTag,2) as varchar) || ')', ', ' order by utr.TagRank) as TopTagsRepresentation
    from UserTagRankings utr
    where utr.TagRank <= 5
    group by utr.OwnerUserId
)
select 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.Views,
    up.UpVotes,
    up.DownVotes,
    up.BadgeCount,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.QuestionCount,
    up.AnswerCount,
    round(up.AvgQuestionScore,2) as AvgQuestionScore,
    round(up.AvgAnswerScore,2) as AvgAnswerScore,
    up.QuestionsWithAcceptedAnswer,
    up.TotalDuplicateLinks,
    up.TotalLinkedPosts,
    up.CurrentlyClosedPosts,
    coalesce(urt.TopTagsRepresentation, '(none)') as TopTags,
    avg(up.Reputation) over (order by up.Reputation desc rows between unbounded preceding and current row) as RunningAvgReputation,
    (select count(*) 
     from Comments c 
     join Posts p on c.PostId = p.Id 
     where p.OwnerUserId = up.UserId and c.CreationDate > (timestamp '2024-10-01 12:34:56' - interval '30' day)
    ) as RecentCommentsCount,
    case 
        when (coalesce(up.QuestionCount,0) + coalesce(up.AnswerCount,0)) > 1000 and up.Reputation > 10000 then 'YES' 
        else 'NO' 
    end as HeavyContributorFlag
from UserPerformance up
left join UserRankedTags urt on up.UserId = urt.OwnerUserId
group by
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.Views,
    up.UpVotes,
    up.DownVotes,
    up.BadgeCount,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.QuestionCount,
    up.AnswerCount,
    up.AvgQuestionScore,
    up.AvgAnswerScore,
    up.QuestionsWithAcceptedAnswer,
    up.TotalDuplicateLinks,
    up.TotalLinkedPosts,
    up.CurrentlyClosedPosts,
    urt.TopTagsRepresentation
order by up.Reputation desc, up.Views desc, up.UserId
limit 50;