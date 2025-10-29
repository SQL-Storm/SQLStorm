with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreationDate,
        p.Score as PostScore,
        p.ViewCount,
        p.Tags,
        -- convert tag string like '<tag1><tag2>' into array by removing leading/trailing angle brackets and splitting on '><'
        regexp_split_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><') as TagArray,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation >= 1000
),
UserTopTags as (
    select 
        rua.UserId,
        s.tag_item as Tag,
        count(*) as TagUsage
    from RecursiveUserActivity rua
    -- expand array to rows in a dialect-neutral way using generate_series on indexes when array is not null
    left join lateral (
        select arr[idx] as tag_item
        from (
            select rua.TagArray as arr
        ) t,
        lateral (
            select gs.idx
            from generate_series(1, case when array_length(t.arr,1) is null then 0 else array_length(t.arr,1) end) as gs(idx)
        ) gs
    ) s on true
    where rua.TagArray is not null
    group by rua.UserId, s.tag_item
),
RankedUserTags as (
    select 
        UserId,
        Tag,
        TagUsage,
        rank() over (partition by UserId order by TagUsage desc) as TagRank
    from UserTopTags
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersHigherScoreThanQuestion
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score
),
PostCloseReasonsSummary as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id 
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserLastCommentDate as (
    select
        c.UserId,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
UserVotesGiven as (
    select
        v.UserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven,
        sum(case when v.VoteTypeId = 6 then 1 else 0 end) as CloseVotesGiven,
        sum(case when v.VoteTypeId = 7 then 1 else 0 end) as ReopenVotesGiven
    from Votes v
    group by v.UserId
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate as UserCreated,
    coalesce(ubc.GoldBadges, 0) as GoldBadgeCount,
    coalesce(ubc.SilverBadges, 0) as SilverBadgeCount,
    coalesce(ubc.BronzeBadges, 0) as BronzeBadgeCount,
    ua.Tag as TopTag,
    ua.TagUsage,
    pas.QuestionId,
    pas.Title as QuestionTitle,
    pas.AnswerCount,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.AnswersHigherScoreThanQuestion,
    pcr.CloseReason,
    pcr.CloseCount,
    ulc.LastCommentDate,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.CloseVotesGiven,
    uv.ReopenVotesGiven,
    case 
        when u.Views is null then 0
        else u.Views
    end as UserViews,
    case 
        when u.Location is null or length(trim(u.Location)) = 0 then 'Unknown'
        else u.Location
    end as LocationNormalized,
    case 
        when u.WebsiteUrl is null then 'No Website'
        when position('http' in u.WebsiteUrl) = 1 then u.WebsiteUrl
        else 'http://' || u.WebsiteUrl
    end as NormalizedWebsiteUrl,
    (select count(*) from Comments c where c.UserId = u.Id and c.Score >= 5) as HighScoreCommentsCount,
    ('User:' || u.DisplayName || ' has reputation ' || u.Reputation) as InfoSummary,
    row_number() over (partition by u.Id order by pas.AnswerCount desc) as QuestionRankByAnswerCount
from Users u
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join RankedUserTags ua on ua.UserId = u.Id and ua.TagRank = 1
left join lateral (
    -- pick a single question per user (the posts owned by the user that are questions) and join their stats
    select pas_inner.*
    from PostAnswerStats pas_inner
    join Posts p on p.Id = pas_inner.QuestionId
    where p.OwnerUserId = u.Id
    order by pas_inner.AnswerCount desc
    limit 1
) pas on true
left join PostCloseReasonsSummary pcr on pcr.PostId = pas.QuestionId
left join UserLastCommentDate ulc on ulc.UserId = u.Id
left join UserVotesGiven uv on uv.UserId = u.Id
where u.Reputation > 1000
  and (ua.TagUsage > 5 or ua.TagUsage is null)
group by
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ua.Tag,
    ua.TagUsage,
    pas.QuestionId,
    pas.Title,
    pas.AnswerCount,
    pas.MaxAnswerScore,
    pas.AvgAnswerScore,
    pas.AnswersHigherScoreThanQuestion,
    pcr.CloseReason,
    pcr.CloseCount,
    ulc.LastCommentDate,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.CloseVotesGiven,
    uv.ReopenVotesGiven,
    u.Views,
    u.Location,
    u.WebsiteUrl
order by u.Reputation desc, pas.AnswerCount desc
limit 100;