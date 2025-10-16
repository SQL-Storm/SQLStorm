-- {"query": "1494.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1056} 
with RecursiveTagCount as (
    select
        p.Id as PostId,
        p.Score,
        regexp_split_to_table(coalesce(p.Tags, ''),'><') as TagRaw
    from 
        Posts p
    where
        p.PostTypeId = 1
        and p.Tags is not null
),
CleanTags as (
    select
        PostId,
        lower(trim(BOTH '<' from trim(TagRaw))) as Tag
    from 
        RecursiveTagCount
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId=1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId=2) as AnswerCount,
        sum(v.BountyAmount) as TotalBountyGiven,
        row_number() over (partition by 1 order by u.Reputation desc) as UserRank
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Votes v on v.UserId = u.Id and v.VoteTypeId = 8
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestionsWithAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        (select count(*) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AnswerCount,
        (select max(a.Score) from Posts a where a.ParentId = q.Id and a.PostTypeId=2) as MaxAnswerScore,
        q.CreationDate,
        q.ClosedDate,
        q.ViewCount,
        array_agg(distinct c.Score) filter(where c.PostId=q.Id) as CommentScores,
        row_number() over (order by q.Score desc nulls last) as RankByScore
    from
        Posts q
        left join Comments c on c.PostId = q.Id
    where
        q.PostTypeId = 1
    group by q.Id
),
UnionBadges as (
    select UserId, 'Gold' as BadgeClass from Badges where Class = 1
    union
    select UserId, 'Silver' from Badges where Class = 2
    union
    select UserId, 'Bronze' from Badges where Class = 3
),
UserBadgeAgg as (
    select
        UserId,
        sum(case when BadgeClass = 'Gold' then 1 else 0 end) as GoldCount,
        sum(case when BadgeClass = 'Silver' then 1 else 0 end) as SilverCount,
        sum(case when BadgeClass = 'Bronze' then 1 else 0 end) as BronzeCount
    from UnionBadges
    group by UserId
),
FilteredPostHistory as (
    select ph.* from PostHistory ph
    inner join PostHistoryTypes pht  on pht.Id = ph.PostHistoryTypeId
    where pht.Name in ('Post Closed', 'Post Reopened', 'Question Protected', 'Question Unprotected')
)

select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    coalesce(uba.GoldCount,0) as GoldBadges,
    coalesce(uba.SilverCount,0) as SilverBadges,
    coalesce(uba.BronzeCount,0) as BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalBountyGiven,
    q.BankroomJSON,
    x.RankByScore,
    podcast.AggregateRecommendedTag AS FavouriteTag,
    podcast.TagUsageCount
from
    UserActivity ua
    left join UserBadgeAgg uba on ua.UserId = uba.UserId
    left join TopQuestionsWithAnswerStats x on x.QuestionId = (
        select pa.Id from Posts pa 
        where pa.PostTypeId=1 and pa.OwnerUserId = ua.UserId 
        order by pa.Score desc nulls last
        limit 1
    )
    left join (
        select
            ct.Tag,
            count(ct.PostId) TagUsageCount,
            json_agg(JSON_BUILD_OBJECT(
                'PostId', Blog.Id,
                'Title', Blog.Title,
                'AnswerCount', Blog.AnswerCount,
                'MaxAnswerScore', Blog.MaxAnswerScore
            )) FILTER (WHERE Blog.Id IS NOT NULL) as AggregateRecommendedTag
        from 
            CleanTags ct
            left join TopQuestionsWithAnswerStats Blog on Blog.QuestionId = ct.PostId
        group by ct.Tag
        order by TagUsageCount desc
        limit 1
    ) podcast on TRUE
where
    ua.Reputation > 1000
    and ua.TotalBountyGiven is not null
    and (coalesce(uba.GoldCount,0) + coalesce(uba.SilverCount,0) + coalesce(uba.BronzeCount,0)) > 0
order by 
    ua.Reputation desc,
    ua.UserId;