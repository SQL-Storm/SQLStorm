-- {"query": "1053.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1680} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from
        Tags t
    join
        Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
),
UserBadgeAgg as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId, b.Class
),
UserVoteStats as (
    select
        v.UserId,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotesGiven,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotesGiven,
        sum(case when vt.Id = 8 then v.BountyAmount else 0 end) as TotalBountyGiven
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
TopAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        p.Title as QuestionTitle,
        u.DisplayName,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts a
    join Posts p on a.ParentId = p.Id and p.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
ClosedQuestions as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes cr on cast(ph.Comment as int) = cr.Id
    where ph.PostHistoryTypeId = 10
),
QuestionWithCloseInfo as (
    select
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        cq.CloseReason,
        cq.CloseDate
    from Posts q
    left join ClosedQuestions cq on q.Id = cq.PostId
    where q.PostTypeId = 1
),
AuthorStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(bagg.BadgeCount, 0) as TotalBadges,
        coalesce(bagg_badge_class1.BadgeCount, 0) as GoldBadges,
        coalesce(bagg_badge_class2.BadgeCount, 0) as SilverBadges,
        coalesce(bagg_badge_class3.BadgeCount, 0) as BronzeBadges,
        coalesce(uvs.UpVotesGiven, 0) as UpVotesGiven,
        coalesce(uvs.DownVotesGiven, 0) as DownVotesGiven,
        coalesce(uvs.TotalBountyGiven, 0) as TotalBountyGiven
    from Users u
    left join UserBadgeAgg bagg on u.Id = bagg.UserId and bagg.Class in (1, 2, 3)
    left join UserBadgeAgg bagg_badge_class1 on u.Id = bagg_badge_class1.UserId and bagg_badge_class1.Class = 1
    left join UserBadgeAgg bagg_badge_class2 on u.Id = bagg_badge_class2.UserId and bagg_badge_class2.Class = 2
    left join UserBadgeAgg bagg_badge_class3 on u.Id = bagg_badge_class3.UserId and bagg_badge_class3.Class = 3
    left join UserVoteStats uvs on u.Id = uvs.UserId
),
AnswerDiff as (
    select
        a.Id,
        a.ParentId,
        q.Score as QuestionScore,
        a.Score as AnswerScore,
        a.Score - q.Score as ScoreDifference
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
),
PopularTags as (
    select distinct
        TagName
    from RecursiveTagCounts
    where Count > 1000
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.CreationDate,
        at.AnswerCount,
        -- Calculated field for length of Title + length of Tags (handle nulls)
        coalesce(length(p.Title), 0) + coalesce(length(p.Tags), 0) as TitleTagLength,
        -- Complex predicate: Check tags intersect with popular tags via LIKE and array
        exists (
            select 1
            from unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as tag
            where tag in (select TagName from PopularTags)
        ) as HasPopularTag
    from Posts p
    left join Posts at on at.Id = p.Id and at.PostTypeId = 1
    where p.PostTypeId in (1, 2)
)
select distinct
    fp.Id as PostId,
    fp.PostTypeId,
    fp.Title,
    fp.Score,
    fp.ViewCount,
    fp.OwnerUserId,
    coalesce(a.DisplayName, fp.OwnerUserId::text) as OwnerName,
    fp.Tags,
    fp.CreationDate,
    fp.AnswerCount,
    fp.TitleTagLength,
    fp.HasPopularTag,
    qci.CloseReason,
    qci.CloseDate,
    asu.Reputation as AuthorReputation,
    asu.GoldBadges,
    asu.SilverBadges,
    asu.BronzeBadges,
    ta.AnswerRank,
    ta.Score as AnswerScore,
    case when ad.ScoreDifference is null then 0 else ad.ScoreDifference end as ScoreDifference,
    -- Window function: running count of posts by the owner ordered by creation date
    row_number() over (partition by fp.OwnerUserId order by fp.CreationDate) as OwnerPostSequence,
    -- Complex string expression combining tags and title (concatenate top 3 tags if possible)
    (
        select string_agg(tag, ', ') from (
            select tag
            from unnest(string_to_array(substring(fp.Tags from 2 for length(fp.Tags)-2), '><')) as tag
            order by tag limit 3
        ) sub
    ) as Top3Tags,
    -- Correlated subquery with NULL logic to count number of gold badges per owner
    (
        select count(*)
        from Badges b
        where b.UserId = fp.OwnerUserId and b.Class = 1
    ) as OwnerGoldBadgeCount
from FilteredPosts fp
left join AuthorStats asu on fp.OwnerUserId = asu.Id
left join TopAnswers ta on ta.ParentId = case when fp.PostTypeId = 2 then fp.ParentId else fp.Id end and ta.Rank = 1
left join AnswerDiff ad on ad.Id = ta.Id
left join QuestionWithCloseInfo qci on fp.Id = qci.Id
left join Users a on a.Id = fp.OwnerUserId
where fp.Score > 5
  and (qci.CloseReason is null or qci.CloseReason not like '%duplicate%')
  and (
    fp.HasPopularTag = true or
    fp.OwnerUserId in (
        select UserId from Badges where Class = 1 limit 100
    )
  )
order by fp.Score desc, fp.ViewCount desc
limit 100;