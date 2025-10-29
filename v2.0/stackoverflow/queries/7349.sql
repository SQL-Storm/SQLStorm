-- {"query": "7349.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2805} 
select 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    coalesce(p.CommentCount, 0) as CommentCount,
    case 
        when p.PostTypeId = 1 then 'Question'
        when p.PostTypeId = 2 then 'Answer'
        when p.PostTypeId = 3 then 'Wiki'
        else 'Other'
    end as PostType,
    case 
        when p.ClosedDate is not null then 'Closed'
        when p.CommunityOwnedDate is not null then 'Community Owned'
        else 'Open'
    end as PostStatus,
    case 
        when p.Tags is not null and p.Tags != '' then 
            substring(p.Tags, 2, length(p.Tags) - 2)
        else ''
    end as TagsList,
    (select count(*) 
     from Comments c 
     where c.PostId = p.Id) as CommentCountSubquery,
    (select count(*) 
     from Votes v 
     where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
    (select count(*) 
     from Votes v 
     where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
    (select count(*) 
     from Badges b 
     where b.UserId = p.OwnerUserId and b.Class = 1) as GoldBadgesCount,
    (select count(*) 
     from Badges b 
     where b.UserId = p.OwnerUserId and b.Class = 2) as SilverBadgesCount,
    (select count(*) 
     from Badges b 
     where b.UserId = p.OwnerUserId and b.Class = 3) as BronzeBadgesCount,
    (select max(ph.CreationDate) 
     from PostHistory ph 
     where ph.PostId = p.Id and ph.PostHistoryTypeId in (1, 2, 3)) as LastEditDate,
    (select count(*) 
     from PostHistory ph 
     where ph.PostId = p.Id and ph.PostHistoryTypeId in (10, 11, 12, 13)) as HistoryActionsCount,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRank,
    rank() over (order by p.Score desc) as ScoreRank,
    dense_rank() over (order by p.ViewCount desc) as ViewRank,
    lag(p.Score, 1) over (order by p.CreationDate) as PreviousScore,
    lead(p.Score, 1) over (order by p.CreationDate) as NextScore,
    avg(p.Score) over (partition by p.OwnerUserId) as AvgUserScore,
    sum(p.Score) over (partition by p.OwnerUserId) as TotalUserScore,
    min(p.CreationDate) over (partition by p.OwnerUserId) as FirstPostDate,
    max(p.CreationDate) over (partition by p.OwnerUserId) as LastPostDate,
    case 
        when p.OwnerUserId is not null then 
            concat('User-', p.OwnerUserId, ': ', u.DisplayName)
        else 
            concat('Anonymous User: ', coalesce(p.OwnerDisplayName, 'Unknown'))
    end as AuthorInfo,
    case 
        when p.Tags is not null and p.Tags != '' then 
            (select count(*) from unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag)
        else 0
    end as TagsCount,
    case 
        when p.PostTypeId = 1 then 
            (select count(*) from Posts p2 where p2.ParentId = p.Id and p2.PostTypeId = 2)
        else 0
    end as AnswerCountInQuestion,
    case 
        when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 
            (select u2.DisplayName from Posts p3 join Users u2 on u2.Id = p3.OwnerUserId where p3.Id = p.AcceptedAnswerId)
        else null
    end as AcceptedAnswerAuthor,
    case 
        when p.PostTypeId = 1 and p.AnswerCount > 0 then 
            (select min(p4.CreationDate) from Posts p4 where p4.ParentId = p.Id and p4.PostTypeId = 2)
        else null
    end as FirstAnswerDate,
    case 
        when p.PostTypeId = 1 and p.AnswerCount > 0 then 
            (select max(p5.CreationDate) from Posts p5 where p5.ParentId = p.Id and p5.PostTypeId = 2)
        else null
    end as LastAnswerDate,
    case 
        when p.PostTypeId = 1 and (p.AnswerCount > 0 or p.CommentCount > 0) then 
            (p.AnswerCount + p.CommentCount + 1)
        else 1
    end as EngagementMetric,
    case 
        when p.ViewCount > 0 then 
            (p.Score * 100.0 / p.ViewCount)
        else null
    end as ScorePerView
from Posts p
left join Users u on u.Id = p.OwnerUserId
left join (
    select PostId, count(*) as CommentCount
    from Comments
    group by PostId
) c on c.PostId = p.Id
left join (
    select 
        p2.Id as PostId,
        count(p3.Id) as FavoriteCount
    from Posts p2
    left join Votes p3 on p3.PostId = p2.Id and p3.VoteTypeId = 5
    group by p2.Id
) f on f.PostId = p.Id
where 
    p.PostTypeId in (1, 2)
    and p.CreationDate >= '2020-01-01'
    and (
        (p.Score > 100 and p.ViewCount > 500)
        or 
        (p.Score > 1000 and p.ViewCount > 1000)
        or 
        (p.Score > 50 and p.ViewCount > 1000)
    )
    and (
        p.Title is not null and length(trim(p.Title)) > 0
    )
    and (
        p.Body is not null and length(trim(p.Body)) > 100
    )
    and (
        u.Reputation > 5000 
        or 
        (
            (select count(*) from Badges b where b.UserId = p.OwnerUserId and b.Class = 1) > 0
        )
    )
    and not exists (
        select 1 
        from PostHistory ph 
        where ph.PostId = p.Id 
        and ph.PostHistoryTypeId = 12 
        and ph.CreationDate >= '2020-01-01'
    )
    and (
        coalesce(p.AnswerCount, 0) >= 3
        or
        coalesce(p.CommentCount, 0) >= 5
    )
    and p.Id % 1000 = 0
union all
select 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    coalesce(p.CommentCount, 0) as CommentCount,
    case 
        when p.PostTypeId = 1 then 'Question'
        when p.PostTypeId = 2 then 'Answer'
        when p.PostTypeId = 3 then 'Wiki'
        else 'Other'
    end as PostType,
    case 
        when p.ClosedDate is not null then 'Closed'
        when p.CommunityOwnedDate is not null then 'Community Owned'
        else 'Open'
    end as PostStatus,
    case 
        when p.Tags is not null and p.Tags != '' then 
            substring(p.Tags, 2, length(p.Tags) - 2)
        else ''
    end as TagsList,
    (select count(*) 
     from Comments c 
     where c.PostId = p.Id) as CommentCountSubquery,
    (select count(*) 
     from Votes v 
     where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
    (select count(*) 
     from Votes v 
     where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
    (select count(*) 
     from Badges b 
     where b.UserId = p.OwnerUserId and b.Class = 1) as GoldBadgesCount,
    (select count(*) 
     from Badges b 
     where b.UserId = p.OwnerUserId and b.Class = 2) as SilverBadgesCount,
    (select count(*) 
     from Badges b 
     where b.UserId = p.OwnerUserId and b.Class = 3) as BronzeBadgesCount,
    (select max(ph.CreationDate) 
     from PostHistory ph 
     where ph.PostId = p.Id and ph.PostHistoryTypeId in (1, 2, 3)) as LastEditDate,
    (select count(*) 
     from PostHistory ph 
     where ph.PostId = p.Id and ph.PostHistoryTypeId in (10, 11, 12, 13)) as HistoryActionsCount,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRank,
    rank() over (order by p.Score desc) as ScoreRank,
    dense_rank() over (order by p.ViewCount desc) as ViewRank,
    lag(p.Score, 1) over (order by p.CreationDate) as PreviousScore,
    lead(p.Score, 1) over (order by p.CreationDate) as NextScore,
    avg(p.Score) over (partition by p.OwnerUserId) as AvgUserScore,
    sum(p.Score) over (partition by p.OwnerUserId) as TotalUserScore,
    min(p.CreationDate) over (partition by p.OwnerUserId) as FirstPostDate,
    max(p.CreationDate) over (partition by p.OwnerUserId) as LastPostDate,
    case 
        when p.OwnerUserId is not null then 
            concat('User-', p.OwnerUserId, ': ', u.DisplayName)
        else 
            concat('Anonymous User: ', coalesce(p.OwnerDisplayName, 'Unknown'))
    end as AuthorInfo,
    case 
        when p.Tags is not null and p.Tags != '' then 
            (select count(*) from unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag)
        else 0
    end as TagsCount,
    case 
        when p.PostTypeId = 1 then 
            (select count(*) from Posts p2 where p2.ParentId = p.Id and p2.PostTypeId = 2)
        else 0
    end as AnswerCountInQuestion,
    case 
        when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 
            (select u2.DisplayName from Posts p3 join Users u2 on u2.Id = p3.OwnerUserId where p3.Id = p.AcceptedAnswerId)
        else null
    end as AcceptedAnswerAuthor,
    case 
        when p.PostTypeId = 1 and p.AnswerCount > 0 then 
            (select min(p4.CreationDate) from Posts p4 where p4.ParentId = p.Id and p4.PostTypeId = 2)
        else null
    end as FirstAnswerDate,
    case 
        when p.PostTypeId = 1 and p.AnswerCount > 0 then 
            (select max(p5.CreationDate) from Posts p5 where p5.ParentId = p.Id and p5.PostTypeId = 2)
        else null
    end as LastAnswerDate,
    case 
        when p.PostTypeId = 1 and (p.AnswerCount > 0 or p.CommentCount > 0) then 
            (p.AnswerCount + p.CommentCount + 1)
        else 1
    end as EngagementMetric,
    case 
        when p.ViewCount > 0 then 
            (p.Score * 100.0 / p.ViewCount)
        else null
    end as ScorePerView
from Posts p
right join Users u on u.Id = p.OwnerUserId
left join Comments c on c.PostId = p.Id
where 
    p.PostTypeId is null 
    and u.Reputation > 10000
    and u.LastAccessDate >= '2020-01-01'
    and (
        length(trim(u.DisplayName)) > 3
    )
    and (
        u.WebsiteUrl is not null and u.WebsiteUrl != ''
    )
    and not exists (
        select 1 
        from Badges b 
        where b.UserId = u.Id and b.Class = 1
    )
    and u.Id % 10 = 0
order by PostId desc
limit 1000;