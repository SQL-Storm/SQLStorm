-- {"query": "1129.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1690} 
with RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as AnswerUser,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionsWithTopAnswers as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.AnswerCount,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName as QuestionUser,
        ra.Id as TopAnswerId,
        ra.Score as TopAnswerScore,
        ra.AnswerUser as TopAnswerUser,
        ra.CreationDate as TopAnswerCreationDate
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join RankedAnswers ra on q.Id = ra.ParentId and ra.rn = 1
    where q.PostTypeId = 1
),
CloseReasonsCount as (
    select ph.PostId, crt.Name as CloseReasonName, count(*) as CloseCount
    from PostHistory ph
    inner join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserBadgeCounts as (
    select 
        b.UserId, 
        b.Class, 
        count(*) as BadgeCount,
        case b.Class
            when 1 then 'Gold'
            when 2 then 'Silver'
            when 3 then 'Bronze'
            else 'Unknown' end as BadgeClassName
    from Badges b
    group by b.UserId, b.Class
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(sum(case when ub.Class = 1 then ub.BadgeCount end),0) as GoldBadges,
        coalesce(sum(case when ub.Class = 2 then ub.BadgeCount end),0) as SilverBadges,
        coalesce(sum(case when ub.Class = 3 then ub.BadgeCount end),0) as BronzeBadges,
        -- Calculate activity span as days between first and last post or comment
        greatest(
            coalesce((
                select max(p.CreationDate) 
                from Posts p 
                where p.OwnerUserId = u.Id
            ), u.CreationDate) - least(
                coalesce((
                    select min(p.CreationDate) 
                    from Posts p 
                    where p.OwnerUserId = u.Id
                ), u.CreationDate), u.CreationDate), interval '1 second') as ActivitySpan
    from Users u
    left join UserBadgeCounts ub on u.Id = ub.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostsWithVoteStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoriteVotes,
        coalesce(sum(v.BountyAmount),0) as TotalBounty
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
AnswerStatistics as (
    select
        p.Id,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        us.Reputation as UserReputation,
        vs.UpVotes,
        vs.DownVotes,
        vs.FavoriteVotes,
        vs.TotalBounty,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        -- Length of the post body treating NULL as zero
        length(coalesce(p.Body, '')) as BodyLength
    from Posts p
    left join Users us on p.OwnerUserId = us.Id
    left join PostsWithVoteStats vs on p.Id = vs.Id
    where p.PostTypeId = 2
),
TopTags as (
    select 
        t.TagName,
        t.Count,
        coalesce(p.Id, -1) as ExcerptPostId,
        coalesce(w.Id, -1) as WikiPostId
    from Tags t
    left join Posts p on t.ExcerptPostId = p.Id
    left join Posts w on t.WikiPostId = w.Id
    where t.Count > 1000
),
CombinedQuestionsAndClosed as (
    select q.Id, q.Title, q.OwnerUserId, q.CreationDate, crc.CloseReasonName, crc.CloseCount
    from QuestionsWithTopAnswers q
    left join CloseReasonsCount crc on q.Id = crc.PostId
    where crc.CloseCount is not null

    union

    select q.Id, q.Title, q.OwnerUserId, q.CreationDate, NULL as CloseReasonName, NULL as CloseCount
    from QuestionsWithTopAnswers q
    where not exists (select 1 from CloseReasonsCount crc where crc.PostId = q.Id)
)
select 
    cq.Id as QuestionId,
    cq.Title,
    cq.CreationDate as QuestionCreationDate,
    cq.QuestionScore,
    cq.AnswerCount,
    substring(cq.Tags from 1 for 200) as SampleTags,
    coi.CloseReasonName,
    coi.CloseCount,
    ra.Id as TopAnswerId,
    ra.Score as TopAnswerScore,
    ra.AnswerUser as TopAnswerUser,
    u.Id as UserId,
    u.DisplayName as UserName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    us.BodyLength as TopAnswerBodyLength,
    us.CommentCount as TopAnswerCommentCount,
    us.UpVotes as TopAnswerUpVotes,
    us.DownVotes as TopAnswerDownVotes,
    us.TotalBounty as TopAnswerBounty,
    dense_rank() over (partition by cq.Id order by ra.Score desc nulls last) as AnswerRank,
    -- String construction with NULL logic: generate a simple URL
    concat('https://stackoverflow.com/questions/', cq.Id, '/', replace(lower(regexp_replace(cq.Title, '[^a-zA-Z0-9]+', '-', 'g')), '--', '-')) as QuestionUrl,
    tt.TagName as PopularTag,
    tt.Count as TagUsageCount,
    -- Correlated subquery example: count of badges for question owner
    (select count(*) from Badges b where b.UserId = cq.OwnerUserId) as OwnerBadgeTotal,
    -- Complex predicate combining: questions with top answers scoring more than 10 and question score more than 5 or question closed as duplicate
    case 
        when ((coalesce(ra.Score,0) > 10 and cq.QuestionScore > 5) or (coi.CloseReasonName = 'Duplicate')) then 'HighEngagement/Duplicate' 
        else 'Other' 
    end as QuestionCategory
from CombinedQuestionsAndClosed cq
left join RankedAnswers ra on cq.Id = ra.ParentId and ra.rn = 1
left join AnswerStatistics us on ra.Id = us.Id
left join UserAggregates u on cq.OwnerUserId = u.Id
left join TopTags tt on position(tt.TagName in cq.Tags) > 0
left join CloseReasonsCount coi on cq.Id = coi.PostId
where cq.CreationDate > now() - interval '365 day'
order by cq.CreationDate desc nulls last, ra.Score desc nulls last
limit 100;